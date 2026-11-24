// SPDX-License-Identifier: MIT
// CPU frame preparation and synthetic Apple5 kernel benchmarks.
// Synthetic coefficients isolate stages and do not model a complete video stream.
#include "dequant_fixture.hpp"
#include "pyrowave_bitstream.hpp"
#include "pyrowaveframing.h"
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <numeric>
#include <string>
#include <vector>
#ifdef __APPLE__
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "pyrowave_common.hpp"
#include "pyrowave_decoder_backend.h"
#include "shaders/pyrowave_msl.h"
#include "PyroWavePresenterSource.h"
#include "color_conversion.hpp"
#include "PyroWaveApple5Source.h"
#endif

namespace {
using Clock = std::chrono::steady_clock;
bool fullDecoderTested = false;
double milliseconds(Clock::time_point from, Clock::time_point to) {
    return std::chrono::duration<double, std::milli>(to - from).count();
}
void statistics(const std::vector<double>& input) {
    if (input.empty()) { std::cout << "null"; return; }
    auto values = input;
    std::sort(values.begin(), values.end());
    const auto quantile = [&](double q) { return values.at(size_t(std::ceil(q * values.size())) - 1); };
    std::cout << "{\"samples\":" << values.size()
              << ",\"mean\":" << std::accumulate(values.begin(), values.end(), 0.0) / values.size()
              << ",\"p50\":" << quantile(.5) << ",\"p95\":" << quantile(.95)
              << ",\"p99\":" << quantile(.99) << "}";
}
struct Profile { int width, height; };
constexpr Profile Profiles[] = {{1280,720}, {1920,1080}, {3840,2160}};
struct CpuFixture {
    PyroWave::BlockLayout layout;
    std::vector<uint8_t> bytes;
    unsigned blocks = 0;
};
CpuFixture cpuFixture(Profile profile, unsigned bitrateMbps, bool zero=false) {
    CpuFixture fixture;
    PWTest::require(fixture.layout.init(profile.width, profile.height,
        PyroWave::ChromaSubsampling::Chroma420), "benchmark layout");
    const size_t budget = zero ? 64 : size_t(bitrateMbps) * 1000000 / 8 / 60;
    std::vector<PyroWave::BitstreamPacket> metadata(size_t(fixture.layout.block_count_32x32));
    std::vector<uint32_t> raw;
    std::array<float,64*64> reference{};
    for (unsigned index = 0; index < metadata.size(); ++index) {
        if (zero && index>0) break;
        auto record = PWTest::coefficientBlock(4 + index % 4, index, reference, 0);
        if (zero) {
            record.assign(8,0);
            PyroWave::BitstreamHeader header{};
            header.payload_words=2; header.sequence=3;
            std::memcpy(record.data(),&header,sizeof(header));
        }
        if (raw.size()*4 + record.size() + 8 > budget) break;
        metadata[index] = {uint32_t(raw.size()), uint32_t(record.size()/4)};
        const size_t offset = raw.size();
        raw.resize(offset + record.size()/4);
        std::memcpy(raw.data() + offset, record.data(), record.size());
        ++fixture.blocks;
    }
    PWTest::require(fixture.blocks > 0, "benchmark fixture has no records");
    fixture.bytes.resize(raw.size()*4 + 8);
    PyroWave::Packet packet{};
    PWTest::require(PyroWave::packetize(fixture.layout, &packet, fixture.bytes.size(),
        fixture.bytes.data(), fixture.bytes.size(), metadata.data(), raw.data()) == 1,
        "benchmark packetization");
    if (packet.offset)
        std::memmove(fixture.bytes.data(), fixture.bytes.data()+packet.offset, packet.size);
    fixture.bytes.resize(packet.size);
    return fixture;
}
void cpuBenchmark(unsigned iterations, unsigned warmup) {
    bool comma = false;
    std::cout << "\"cpu\":[";
    for (auto profile : Profiles) for (unsigned budget : {150u,300u,500u,1000u}) {
        auto fixture = cpuFixture(profile, budget);
        PyroWaveFraming::Frame framed;
        PyroWave::BitstreamParser parser;
        parser.init(&fixture.layout);
        std::string error;
        std::vector<double> copyTimes, validationTimes, packetTimes, totalTimes;
        for (unsigned sample=0; sample < warmup+iterations; ++sample) {
            const auto begin = Clock::now();
            std::unique_ptr<uint8_t,decltype(&std::free)> copy(
                static_cast<uint8_t*>(std::malloc(fixture.bytes.size())), &std::free);
            PWTest::require(bool(copy), "benchmark copy allocation");
            std::memcpy(copy.get(), fixture.bytes.data(), fixture.bytes.size());
            const auto copied = Clock::now();
            if (!PyroWaveFraming::parse(copy.get(), fixture.bytes.size(),
                    {profile.width,profile.height,false}, framed, error))
                throw std::runtime_error(error);
            const auto validated = Clock::now();
            parser.clear();
            for (auto span : framed.spans)
                PWTest::require(parser.push_packet(copy.get()+span.offset,span.size), "benchmark codec parser");
            PWTest::require(parser.decode_is_ready(false) &&
                parser.get_decoded_blocks()==int(fixture.blocks), "benchmark codec completeness");
            const auto completed = Clock::now();
            if (sample < warmup) continue;
            copyTimes.push_back(milliseconds(begin,copied));
            validationTimes.push_back(milliseconds(copied,validated));
            packetTimes.push_back(milliseconds(validated,completed));
            totalTimes.push_back(milliseconds(begin,completed));
        }
        if (comma) std::cout << ",";
        comma = true;
        std::cout << "{\"width\":" << profile.width << ",\"height\":" << profile.height
                  << ",\"budget_mbps\":" << budget << ",\"bytes\":" << fixture.bytes.size()
                  << ",\"blocks\":" << fixture.blocks << ",\"copy_ms\":";
        statistics(copyTimes);
        std::cout << ",\"validation_ms\":"; statistics(validationTimes);
        std::cout << ",\"codec_push_ms\":"; statistics(packetTimes);
        std::cout << ",\"total_cpu_ms\":"; statistics(totalTimes);
        std::cout << "}";
    }
    std::cout << "]";
}
#ifdef PW_BENCHMARK_REFERENCE
extern "C" bool benchmark_reference_parse(const uint8_t*,size_t,int,int,uint32_t*);
void pairedValidation(unsigned iterations,unsigned warmup) {
    std::cout << ",\"paired_validation\":[";
    bool comma=false;
    for (auto profile:Profiles) for (unsigned budget:{150u,300u,500u,1000u}) {
        auto fixture=cpuFixture(profile,budget);
        PyroWaveFraming::Frame frame;
        std::string error;
        std::vector<double> referenceTimes,candidateTimes;
        for (unsigned sample=0;sample<warmup+iterations;++sample) {
            auto reference=[&] {
                uint32_t blocks=0;
                const auto begin=Clock::now();
                const bool valid=benchmark_reference_parse(fixture.bytes.data(),fixture.bytes.size(),
                    profile.width,profile.height,&blocks);
                const auto end=Clock::now();
                PWTest::require(valid && blocks==fixture.blocks,"paired reference validation");
                if (sample>=warmup) referenceTimes.push_back(milliseconds(begin,end));
            };
            auto candidate=[&] {
                const auto begin=Clock::now();
                const bool valid=PyroWaveFraming::parse(fixture.bytes.data(),fixture.bytes.size(),
                    {profile.width,profile.height,false},frame,error);
                const auto end=Clock::now();
                PWTest::require(valid && frame.blockRecords==fixture.blocks,"paired candidate validation");
                if (sample>=warmup) candidateTimes.push_back(milliseconds(begin,end));
            };
            if (sample%2) { candidate(); reference(); }
            else { reference(); candidate(); }
        }
        if (comma) std::cout << ",";
        comma=true;
        std::cout << "{\"width\":" << profile.width << ",\"height\":" << profile.height
                  << ",\"budget_mbps\":" << budget << ",\"reference_ms\":";
        statistics(referenceTimes);
        std::cout << ",\"candidate_ms\":"; statistics(candidateTimes);
        std::cout << "}";
    }
    std::cout << "]";
}
#endif
#ifdef __APPLE__
struct alignas(8) Registers { int resolution[2]; int layer, offset, stride; };
struct HostDecoderDevice {
    std::unique_ptr<pyrowave_device_opaque> value = std::make_unique<pyrowave_device_opaque>();
    HostDecoderDevice(id<MTLDevice> metal, id<MTLComputePipelineState> dequant) {
        // Offline lab assembly uses the real decoder and pipeline helpers on the
        // host GPU. Production device admission remains in the normal factory.
        value->mtl = metal;
        value->decoder_only = true;
        value->portable_dequant = true;
        value->precision = 1;
        value->dequant_pipeline = dequant;
        auto library = PyroWave::compile_library(value.get(),PyroWave::idwt_fp16_storage_msl_source,
            "Host benchmark iDWT");
        PWTest::require(library != nil,"host benchmark iDWT library");
        for (unsigned shift=0;shift<2;++shift)
            value->idwt_pipeline[shift] = PyroWave::create_pipeline_bool_constant(value.get(),
                library,"pyrowave_idwt",PyroWave::IdwtThreadgroupSize,0,shift!=0);
        PWTest::require(value->idwt_pipeline[0] && value->idwt_pipeline[1],"host benchmark iDWT pipelines");
        auto sampler = [MTLSamplerDescriptor new];
        sampler.minFilter=MTLSamplerMinMagFilterNearest;
        sampler.magFilter=MTLSamplerMinMagFilterNearest;
        sampler.mipFilter=MTLSamplerMipFilterNearest;
        sampler.sAddressMode=MTLSamplerAddressModeMirrorRepeat;
        sampler.tAddressMode=MTLSamplerAddressModeMirrorRepeat;
        sampler.rAddressMode=MTLSamplerAddressModeMirrorRepeat;
        value->mirror_repeat_sampler=[metal newSamplerStateWithDescriptor:sampler];
        PWTest::require(value->mirror_repeat_sampler != nil,"host benchmark sampler");
    }
};
void fullDecoderBenchmark(id<MTLDevice> metal,id<MTLComputePipelineState> dequant,
                          id<MTLCommandQueue> queue,unsigned iterations,unsigned warmup) {
    HostDecoderDevice engine(metal,dequant);
    NSError* error=nil;
    auto library=[metal newLibraryWithSource:@(PWClient::PresenterSource) options:nil error:&error];
    if (!library) throw std::runtime_error(error.localizedDescription.UTF8String);
    auto descriptor=[MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction=[library newFunctionWithName:@"pw_vertex"];
    descriptor.fragmentFunction=[library newFunctionWithName:@"pw_fragment"];
    descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    auto presenter=[metal newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!presenter) throw std::runtime_error(error.localizedDescription.UTF8String);
    struct Case { Profile profile; unsigned budget; bool zero; };
    std::vector<Case> cases{{{128,128},0,true},{{320,180},0,true}};
    for (auto profile:Profiles) for (unsigned budget:{150u,300u,500u,1000u})
        cases.push_back({profile,budget,false});
    std::cout << ",\"full_decoder\":{\"method\":\"host-lab-offscreen-split-serial\","
                 "\"production_backend_candidate\":"
              << (pw_decoder_backend_is_candidate((__bridge void*)metal)?"true":"false")
              << ",\"zero_profiles_checked\":2,\"cases\":[";
    bool comma=false;
    for (const auto& test:cases) { @autoreleasepool {
        auto fixture=cpuFixture(test.profile,test.budget,test.zero);
        struct Decoder {
            pyrowave_decoder value=nullptr;
            ~Decoder() { if (value) pyrowave_decoder_destroy(value); }
        } decoder;
        pyrowave_decoder_create_info info{};
        info.device=engine.value.get(); info.width=test.profile.width; info.height=test.profile.height;
        info.chroma=PYROWAVE_CHROMA_SUBSAMPLING_420;
        PWTest::require(pyrowave_decoder_create(&info,&decoder.value)==PYROWAVE_SUCCESS,"host benchmark decoder");
        id<MTLTexture> planes[3];
        pyrowave_gpu_buffers buffers{};
        for (unsigned plane=0;plane<3;++plane) {
            auto texture=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                width:info.width/(plane?2:1) height:info.height/(plane?2:1) mipmapped:NO];
            texture.storageMode=MTLStorageModePrivate;
            texture.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
            planes[plane]=[metal newTextureWithDescriptor:texture];
            PWTest::require(planes[plane]!=nil,"host benchmark plane");
            buffers.planes[plane]=(__bridge void*)planes[plane];
        }
        auto target=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:info.width height:info.height mipmapped:NO];
        target.storageMode=MTLStorageModePrivate;
        target.usage=MTLTextureUsageRenderTarget;
        auto output=[metal newTextureWithDescriptor:target];
        PWTest::require(output!=nil,"host benchmark presentation target");
        PyroWaveFraming::Frame framed;
        std::string framingError;
        std::vector<double> decodeTimes,colorTimes,readyTimes,prepareTimes;
        for (unsigned sample=0;sample<warmup+iterations;++sample) { @autoreleasepool {
            const double received=CACurrentMediaTime();
            const auto begin=Clock::now();
            if (!PyroWaveFraming::parse(fixture.bytes.data(),fixture.bytes.size(),
                    {info.width,info.height,false},framed,framingError))
                throw std::runtime_error(framingError);
            pyrowave_decoder_clear(decoder.value);
            for (auto span:framed.spans)
                PWTest::require(pyrowave_decoder_push_packet(decoder.value,fixture.bytes.data()+span.offset,
                    span.size)==PYROWAVE_SUCCESS,"host benchmark packet");
            PWTest::require(pyrowave_decoder_decode_is_ready(decoder.value,false),"host benchmark readiness");
            auto decode=[queue commandBuffer];
            PWTest::require(decode!=nil,"host benchmark decode command");
            PWTest::require(pyrowave_decoder_decode_gpu_buffer(decoder.value,(__bridge void*)decode,
                &buffers)==PYROWAVE_SUCCESS,"host benchmark decode encoding");
            [decode commit];
            const auto submitted=Clock::now();
            auto conversion=[queue commandBuffer];
            auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture=output;
            pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;
            pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            auto render=[conversion renderCommandEncoderWithDescriptor:pass];
            PWTest::require(render!=nil,"host benchmark conversion encoder");
            auto color=PWClient::colorConversion(1,false);
            [render setRenderPipelineState:presenter];
            for (unsigned plane=0;plane<3;++plane) [render setFragmentTexture:planes[plane] atIndex:plane];
            [render setFragmentBytes:&color length:sizeof(color) atIndex:0];
            [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [render endEncoding]; [conversion commit]; [conversion waitUntilCompleted]; [decode waitUntilCompleted];
            PWTest::require(decode.status==MTLCommandBufferStatusCompleted &&
                conversion.status==MTLCommandBufferStatusCompleted,"host benchmark GPU execution");
            if (sample<warmup) continue;
            prepareTimes.push_back(milliseconds(begin,submitted));
            if (decode.GPUStartTime>0 && decode.GPUEndTime>decode.GPUStartTime)
                decodeTimes.push_back((decode.GPUEndTime-decode.GPUStartTime)*1000);
            if (conversion.GPUStartTime>0 && conversion.GPUEndTime>conversion.GPUStartTime)
                colorTimes.push_back((conversion.GPUEndTime-conversion.GPUStartTime)*1000);
            if (conversion.GPUEndTime>=received && conversion.GPUEndTime<=CACurrentMediaTime())
                readyTimes.push_back((conversion.GPUEndTime-received)*1000);
        }}
        uint64_t hash=14695981039346656037ull;
        for (unsigned plane=0;plane<4;++plane) { @autoreleasepool {
            id<MTLTexture> texture=plane<3?planes[plane]:output;
            const size_t channels=plane<3?1:4;
            const size_t rowBytes=(texture.width*channels+255)&~size_t(255);
            auto data=[metal newBufferWithLength:rowBytes*texture.height options:MTLResourceStorageModeShared];
            auto command=[queue commandBuffer]; auto blit=[command blitCommandEncoder];
            PWTest::require(data && command && blit,"host benchmark readback resources");
            [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                sourceSize:MTLSizeMake(texture.width,texture.height,1) toBuffer:data destinationOffset:0
                destinationBytesPerRow:rowBytes destinationBytesPerImage:rowBytes*texture.height];
            [blit endEncoding]; [command commit]; [command waitUntilCompleted];
            PWTest::require(command.status==MTLCommandBufferStatusCompleted,"host benchmark readback command");
            const auto bytes=static_cast<const uint8_t*>(data.contents);
            for (size_t y=0;y<texture.height;++y) for (size_t x=0;x<texture.width*channels;++x) {
                const uint8_t value=bytes[y*rowBytes+x];
                if (test.zero && plane<3)
                    PWTest::require(std::abs(int(value)-128)<=1,"host benchmark zero frame reconstruction");
                hash=(hash^value)*1099511628211ull;
            }
        }}
        if (comma) std::cout << ",";
        comma=true;
        std::cout << "{\"width\":" << info.width << ",\"height\":" << info.height
                  << ",\"budget_mbps\":" << test.budget << ",\"zero_frame\":" << (test.zero?"true":"false")
                  << ",\"output_hash\":" << std::quoted(std::to_string(hash)) << ",\"prepare_ms\":";
        statistics(prepareTimes);
        std::cout << ",\"decode_gpu_ms\":"; statistics(decodeTimes);
        std::cout << ",\"color_gpu_ms\":"; statistics(colorTimes);
        std::cout << ",\"ready_gpu_end_ms\":"; statistics(readyTimes);
        std::cout << "}";
    }}
    std::cout << "]}";
    fullDecoderTested = true;
}
void gpuBenchmark(unsigned iterations, unsigned warmup, const std::string& shaderPath) {
    @autoreleasepool {
        auto device = MTLCreateSystemDefaultDevice();
        if (!device) { std::cout << "\"gpu\":{\"available\":false,\"cases\":[]}"; return; }
        NSError* error = nil;
        auto options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion2_2;
        NSString* source = @(wavelet_dequant_apple5_msl_source);
        if (!shaderPath.empty()) {
            source = [NSString stringWithContentsOfFile:@(shaderPath.c_str())
                encoding:NSUTF8StringEncoding error:&error];
            if (!source) throw std::runtime_error("cannot read benchmark shader");
        }
        auto library = [device newLibraryWithSource:source options:options error:&error];
        if (!library) throw std::runtime_error(error.localizedDescription.UTF8String);
        auto function = [library newFunctionWithName:@"pyrowave_wavelet_dequant"];
        auto pipeline = [device newComputePipelineStateWithFunction:function error:&error];
        if (!pipeline) throw std::runtime_error(error.localizedDescription.UTF8String);
        PWTest::require(pipeline.maxTotalThreadsPerThreadgroup >= 128, "benchmark thread limit");
        auto queue = [device newCommandQueue];
        PWTest::require(queue != nil, "benchmark command queue");
        std::cout << "\"gpu\":{\"available\":true,\"name\":"
                  << std::quoted(device.name.UTF8String)
                  << ",\"thread_width\":" << pipeline.threadExecutionWidth << ",\"cases\":[";
        bool comma = false;
        for (auto profile : Profiles) {
            const unsigned width = (unsigned(profile.width)+31u)&~31u;
            const unsigned height = (unsigned(profile.height)+31u)&~31u;
            auto descriptor = [MTLTextureDescriptor new];
            descriptor.textureType = MTLTextureType2DArray;
            descriptor.pixelFormat = MTLPixelFormatR32Float;
            descriptor.width=width; descriptor.height=height; descriptor.arrayLength=2;
            descriptor.storageMode=MTLStorageModePrivate;
            descriptor.usage=MTLTextureUsageShaderWrite;
            auto output = [device newTextureWithDescriptor:descriptor];
            const size_t rowBytes = (size_t(width)*sizeof(float)+255)&~size_t(255);
            auto readback = [device newBufferWithLength:rowBytes*height options:MTLResourceStorageModeShared];
            PWTest::require(output && readback, "benchmark output allocation");
            for (unsigned seed=0; seed<8; ++seed) {
                PWTest::DequantFixture fixture;
                PWTest::makeFixture(fixture,seed);
                PyroWave::BitstreamParser parser;
                PWTest::parseFixture(fixture,parser);
                const auto& words = parser.payload();
                auto payload = [device newBufferWithLength:words.size()*4+16 options:MTLResourceStorageModeShared];
                PWTest::require(payload != nil,"benchmark payload allocation");
                std::memset(payload.contents,0,payload.length);
                std::memcpy(payload.contents,words.data(),words.size()*4);
                std::vector<uint32_t> offsets(size_t(width/32)*(height/32));
                for (unsigned y=0; y<height/32; ++y) for (unsigned x=0; x<width/32; ++x)
                    offsets[size_t(y)*(width/32)+x]=parser.dequant_offsets().at(
                        size_t(fixture.blockOffset)+(y%2)*2+x%2);
                auto lookup = [device newBufferWithBytes:offsets.data()
                    length:offsets.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
                PWTest::require(lookup != nil,"benchmark lookup allocation");
                Registers registers{{int(width),int(height)},1,0,int(width/32)};
                std::vector<double> gpuTimes, submitTimes;
                for (unsigned sample=0; sample < warmup+iterations; ++sample) {
                    @autoreleasepool {
                        const auto begin = Clock::now();
                        auto command = [queue commandBuffer];
                        auto encoder = [command computeCommandEncoder];
                        PWTest::require(command && encoder, "benchmark command allocation");
                        [encoder setComputePipelineState:pipeline];
                        [encoder setBuffer:payload offset:0 atIndex:0];
                        [encoder setBytes:&registers length:sizeof(registers) atIndex:1];
                        [encoder setBuffer:lookup offset:0 atIndex:2];
                        [encoder setTexture:output atIndex:0];
                        [encoder dispatchThreadgroups:MTLSizeMake(width/32,height/32,1)
                            threadsPerThreadgroup:MTLSizeMake(128,1,1)];
                        [encoder endEncoding];
                        [command commit];
                        const auto submitted = Clock::now();
                        [command waitUntilCompleted];
                        PWTest::require(command.status==MTLCommandBufferStatusCompleted,"benchmark GPU command");
                        const double elapsed=(command.GPUEndTime-command.GPUStartTime)*1000;
                        if (sample>=warmup) {
                            submitTimes.push_back(milliseconds(begin,submitted));
                            if (command.GPUStartTime>0 && elapsed>0 && std::isfinite(elapsed))
                                gpuTimes.push_back(elapsed);
                        }
                    }
                }
                // Readback and exhaustive reference comparison are outside timed work.
                auto command = [queue commandBuffer];
                auto blit = [command blitCommandEncoder];
                PWTest::require(command && blit,"benchmark readback command");
                [blit copyFromTexture:output sourceSlice:1 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                    sourceSize:MTLSizeMake(width,height,1) toBuffer:readback destinationOffset:0
                    destinationBytesPerRow:rowBytes destinationBytesPerImage:rowBytes*height];
                [blit endEncoding]; [command commit]; [command waitUntilCompleted];
                PWTest::require(command.status==MTLCommandBufferStatusCompleted,"benchmark readback");
                double maximumError=0;
                for (unsigned y=0;y<height;++y) {
                    const auto row=reinterpret_cast<const float*>(
                        static_cast<const uint8_t*>(readback.contents)+size_t(y)*rowBytes);
                    for (unsigned x=0;x<width;++x) {
                        const float expected=fixture.expected[(y%64)*64+x%64];
                        const double delta=std::abs(double(row[x])-expected);
                        PWTest::require(std::isfinite(row[x]) &&
                            delta<=1e-5*std::abs(double(expected))+1e-4,"benchmark coefficient mismatch");
                        maximumError=std::max(maximumError,delta);
                    }
                }
                if (comma) std::cout << ",";
                comma=true;
                std::cout << "{\"width\":" << profile.width << ",\"height\":" << profile.height
                          << ",\"coefficient_width\":" << width << ",\"coefficient_height\":" << height
                          << ",\"fixture\":" << seed << ",\"coefficients_checked\":" << size_t(width)*height
                          << ",\"maximum_error\":" << maximumError << ",\"gpu_ms\":";
                statistics(gpuTimes);
                std::cout << ",\"cpu_submit_ms\":"; statistics(submitTimes);
                std::cout << "}";
            }
        }
        std::cout << "]}";
        fullDecoderBenchmark(device,pipeline,queue,iterations,warmup);
    }
}
#endif
}
int main(int argc,char** argv) try {
    unsigned iterations=100, warmup=20;
    bool cpuOnly=false;
    std::string shaderPath;
    for (int i=1;i<argc;++i) {
        const std::string option=argv[i];
        if (option=="--cpu-only") cpuOnly=true;
        else if ((option=="--iterations" || option=="--warmup" || option=="--shader-source") && i+1<argc) {
            const std::string value=argv[++i];
            if (option=="--shader-source") shaderPath=value;
            else {
                size_t end=0;
                const auto count=std::stoul(value,&end);
                PWTest::require(end==value.size() && count<=10000 &&
                    (option=="--warmup" || count>0),"invalid benchmark sample count");
                if (option=="--iterations") iterations=unsigned(count); else warmup=unsigned(count);
            }
        } else throw std::runtime_error("invalid benchmark argument");
    }
    std::cout << std::setprecision(9) << "{\"schema_version\":1,\"iterations\":" << iterations
              << ",\"warmup\":" << warmup
              << ",\"synthetic_workload\":true,"
                 "\"physical_apple_tv_tested\":false,";
    cpuBenchmark(iterations,warmup);
#ifdef PW_BENCHMARK_REFERENCE
    pairedValidation(iterations,warmup);
#endif
    std::cout << ",";
    if (cpuOnly)
        std::cout << "\"gpu\":{\"available\":false,\"cases\":[]}";
    else {
#ifdef __APPLE__
        gpuBenchmark(iterations,warmup,shaderPath);
#else
        std::cout << "\"gpu\":{\"available\":false,\"cases\":[]}";
#endif
    }
    std::cout << ",\"full_decoder_tested\":" << (fullDecoderTested?"true":"false") << "}\n";
    return 0;
} catch(const std::exception& error) { std::cerr << error.what() << "\n"; return 1; }
