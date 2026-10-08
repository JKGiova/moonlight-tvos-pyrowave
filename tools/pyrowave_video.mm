// SPDX-License-Identifier: MIT
// Offline harness. Synchronous waits and readback here are not a live renderer.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "pyrowave_metal.h"
#include "pyrowave_decoder_backend.h"
#include "pyrowave_file.hpp"
#include "yuv4mpeg.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <vector>
using Clock = std::chrono::steady_clock;
static void check(pyrowave_result result) {
    if(result!=PYROWAVE_SUCCESS)throw std::runtime_error(pyrowave_result_to_string(result));
}
struct Engine {
    pyrowave_device device=nullptr;
    pyrowave_encoder encoder=nullptr;
    pyrowave_decoder decoder=nullptr;
    id<MTLDevice> metal=nil;
    Engine(bool decoderOnly=false,bool portable=false) {
        metal=MTLCreateSystemDefaultDevice();
        if(!metal)throw std::runtime_error("no Metal GPU");
        pyrowave_device_create_info info{};info.mtl_device=(__bridge void*)metal;
        check(decoderOnly ? pw_decoder_device_create(&info,portable,&device) : pyrowave_device_create(&info,&device));
    }
    ~Engine(){if(encoder)pyrowave_encoder_destroy(encoder);if(decoder)pyrowave_decoder_destroy(decoder);if(device)pyrowave_device_destroy(device);}
};
static void encode(const char* inputPath,const char* outputPath,const char* budgetText) {
    size_t end=0;const auto parsedBudget=std::stoull(budgetText,&end);
    if(end!=std::string(budgetText).size()||parsedBudget<64||parsedBudget>16U*1024U*1024U)throw std::runtime_error("bytes-per-frame must be 64..16777216");
    YUV4MPEGFile input;if(!input.open_read(inputPath))throw std::runtime_error("cannot read Y4M input");
    if(input.get_format()!=YUV4MPEGFile::Format::YUV420P)throw std::runtime_error("only 8-bit YUV420P input is supported in this harness");
    PWFile::Header header{uint32_t(input.get_width()),uint32_t(input.get_height()),uint32_t(input.get_frame_rate_num()),uint32_t(input.get_frame_rate_den()),input.is_full_range()};
    // Validate the header through the same reader used for external fixtures.
    std::stringstream headerCheck;PWFile::writeHeader(headerCheck,header);PWFile::readHeader(headerCheck);
    Engine engine;pyrowave_encoder_create_info info{};info.device=engine.device;
    info.width=int(header.width);info.height=int(header.height);info.chroma=PYROWAVE_CHROMA_SUBSAMPLING_420;
    check(pyrowave_encoder_create(&info,&engine.encoder));
    const size_t ySize=size_t(header.width)*header.height,cSize=ySize/4;
    std::vector<uint8_t> yuv(ySize+2*cSize),bitstream;
    pyrowave_cpu_buffer buffer{};buffer.width=info.width;buffer.height=info.height;buffer.format=PYROWAVE_CPU_BUFFER_FORMAT_YUV420P;
    buffer.data[0]=yuv.data();buffer.data[1]=yuv.data()+ySize;buffer.data[2]=yuv.data()+ySize+cSize;
    buffer.row_stride_in_bytes[0]=header.width;buffer.row_stride_in_bytes[1]=buffer.row_stride_in_bytes[2]=header.width/2;
    buffer.plane_size_in_bytes[0]=ySize;buffer.plane_size_in_bytes[1]=buffer.plane_size_in_bytes[2]=cSize;
    std::ofstream output(outputPath,std::ios::binary);if(!output)throw std::runtime_error("cannot create output");PWFile::writeHeader(output,header);
    pyrowave_rate_control rc{size_t(parsedBudget)};uint64_t frames=0;PyroWaveFraming::Frame validation;
    while(input.begin_frame()) {
        @autoreleasepool {
            for(unsigned p=0;p<3;++p)if(!input.read(buffer.data[p],buffer.plane_size_in_bytes[p]))throw std::runtime_error("truncated Y4M frame");
            check(pyrowave_encoder_encode_cpu_synchronous(engine.encoder,&buffer,&rc));
            const void *raw=nullptr,*meta=nullptr;size_t rawSize=0,metaSize=0;
            check(pyrowave_encoder_get_mapped_raw_bitstream(engine.encoder,&raw,&rawSize,&meta,&metaSize));
            // Output includes one 8-byte record header per active block.
            const size_t overhead=size_t(PyroWaveFraming::maxBlockCount({info.width,info.height,false}))*8+8;
            if(rawSize>PWFile::MaxFrameBytes||overhead>PWFile::MaxFrameBytes-rawSize)throw std::runtime_error("encoder scratch limit exceeded");
            bitstream.resize(rawSize+overhead);
            size_t count=0;check(pyrowave_encoder_compute_num_packets(engine.encoder,bitstream.size(),&count));
            if(count!=1)throw std::runtime_error("expected a single offline packet");
            pyrowave_packet packet{};check(pyrowave_encoder_packetize(engine.encoder,&packet,bitstream.size(),&count,bitstream.data(),bitstream.size()));
            if(count!=1||packet.offset>bitstream.size()||packet.size>bitstream.size()-packet.offset)throw std::runtime_error("invalid packetization output");
            if(packet.offset)std::move(bitstream.begin()+packet.offset,bitstream.begin()+packet.offset+packet.size,bitstream.begin());
            bitstream.resize(packet.size);PWFile::validateFrame(bitstream,header,validation);
            PWFile::writeFrame(output,bitstream.data(),bitstream.size());++frames;
        }
    }
    if(!frames)throw std::runtime_error("input has no frames");
    output.flush();if(!output)throw std::runtime_error("output flush failed");
    std::cout<<"{\"frames\":"<<frames<<",\"backend\":\"metal-native-apple7\",\"bitstream_id\":\"186f0393\",\"auto_qualified\":false}\n";
}
static double percentile(std::vector<double> values,double q) {
    std::sort(values.begin(),values.end());return values.at(size_t(std::ceil(q*values.size()))-1);
}
static void decode(const char* inputPath,const char* outputPath,const char* metricsPath,bool portable=false) {
    std::ifstream input(inputPath,std::ios::binary);if(!input)throw std::runtime_error("cannot read PyroWave file");
    const auto header=PWFile::readHeader(input);Engine engine(true,portable);
    pyrowave_decoder_create_info info{};info.device=engine.device;info.width=int(header.width);info.height=int(header.height);info.chroma=PYROWAVE_CHROMA_SUBSAMPLING_420;
    check(pyrowave_decoder_create(&info,&engine.decoder));
    id<MTLCommandQueue> queue=[engine.metal newCommandQueue];if(!queue)throw std::runtime_error("cannot create Metal queue");
    id<MTLTexture> textures[3];pyrowave_gpu_buffers buffers{};
    for(unsigned p=0;p<3;++p) {
        auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:header.width/(p?2:1) height:header.height/(p?2:1) mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared;descriptor.usage=MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead;
        textures[p]=[engine.metal newTextureWithDescriptor:descriptor];if(!textures[p])throw std::runtime_error("cannot create output texture");buffers.planes[p]=(__bridge void*)textures[p];
    }
    std::ofstream output(outputPath,std::ios::binary);if(!output)throw std::runtime_error("cannot create decoded output");
    output<<"YUV4MPEG2 W"<<header.width<<" H"<<header.height<<" F"<<header.fpsNumerator<<":"<<header.fpsDenominator<<" Ip A0:0 C420jpeg XCOLORRANGE="<<(header.fullRange?"FULL":"LIMITED")<<"\n";
    std::vector<uint8_t> payload,plane(size_t(header.width)*header.height);PyroWaveFraming::Frame parsed;
    std::vector<double> gpuTimes;uint64_t count=0;
    while(PWFile::readFrame(input,payload)) {
        @autoreleasepool {
            PWFile::validateFrame(payload,header,parsed);pyrowave_decoder_clear(engine.decoder);
            for(const auto& span:parsed.spans)check(pyrowave_decoder_push_packet(engine.decoder,payload.data()+span.offset,span.size));
            if(!pyrowave_decoder_decode_is_ready(engine.decoder,false))throw std::runtime_error("complete frame not ready");
            id<MTLCommandBuffer> command=[queue commandBuffer];if(!command)throw std::runtime_error("cannot create command buffer");
            check(pyrowave_decoder_decode_gpu_buffer(engine.decoder,(__bridge void*)command,&buffers));
            [command commit];[command waitUntilCompleted];
            if(command.status!=MTLCommandBufferStatusCompleted)throw std::runtime_error("GPU decode command failed");
            const double ms=(command.GPUEndTime-command.GPUStartTime)*1000;
            if(command.GPUStartTime>0&&ms>0&&std::isfinite(ms))gpuTimes.push_back(ms);
            output<<"FRAME\n";
            for(unsigned p=0;p<3;++p) {
                const auto width=textures[p].width,height=textures[p].height;
                [textures[p] getBytes:plane.data() bytesPerRow:width fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
                output.write(reinterpret_cast<const char*>(plane.data()),std::streamsize(width*height));
            }
            if(!output)throw std::runtime_error("decoded output write failed");++count;
        }
    }
    if(!count)throw std::runtime_error("no decoded frames");
    output.flush();if(!output)throw std::runtime_error("decoded output flush failed");
    std::ofstream metrics(metricsPath);if(!metrics)throw std::runtime_error("cannot create metrics");
    metrics<<"{\"frames\":"<<count<<",\"backend\":\""<<pw_decoder_backend_name(engine.device)<<"\",\"gpu_timing_samples\":"<<gpuTimes.size()<<",\"method\":\"offline-serial-with-readback\",\"auto_qualified\":false,\"gpu_decode_ms\":";
    if(gpuTimes.empty())metrics<<"null";else metrics<<"{\"p50\":"<<percentile(gpuTimes,.5)<<",\"p95\":"<<percentile(gpuTimes,.95)<<",\"p99\":"<<percentile(gpuTimes,.99)<<"}";
    metrics<<"}\n";metrics.flush();if(!metrics)throw std::runtime_error("metrics write failed");
}
int main(int argc,char** argv) {
    @autoreleasepool { try {
        if(argc==2&&std::string(argv[1])=="--probe") {
            id<MTLDevice> device=MTLCreateSystemDefaultDevice();
            const bool supported=device&&pyrowave_device_is_supported((__bridge void*)device);
            const bool candidate=device&&pw_decoder_backend_is_candidate((__bridge void*)device);
            std::cout<<"{\"device_available\":"<<(device?"true":"false")<<",\"native_backend_supported\":"<<(supported?"true":"false")<<",\"decoder_backend_candidate\":"<<(candidate?"true":"false")<<",\"auto_qualified\":false}\n";
            return 0;
        }
        if(argc==2&&std::string(argv[1])=="--version"){std::cout<<"pyrowave-video bitstream=186f0393 native+portable-Metal offline-tool\n";return 0;}
        if(argc==5&&std::string(argv[1])=="encode")encode(argv[2],argv[3],argv[4]);
        else if(argc==5&&std::string(argv[1])=="decode")decode(argv[2],argv[3],argv[4]);
        else if(argc==5&&std::string(argv[1])=="decode-portable")decode(argv[2],argv[3],argv[4],true);
        else throw std::runtime_error("Usage: pyrowave-video encode input.y4m output.pyrowave bytes_per_frame | decode[-portable] input.pyrowave reconstructed.y4m metrics.json");
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;} }
}
