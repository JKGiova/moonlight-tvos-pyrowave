// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "PyroWaveHDRPresenter.h"
#include <array>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static void check(bool value,const char* message) { if (!value) throw std::runtime_error(message); }
int main() { @autoreleasepool { try {
    auto device=MTLCreateSystemDefaultDevice();
    if (!device) { std::cout<<"{\"gpu_available\":false}\n";return 0; }
    NSData* nameData=[NSJSONSerialization dataWithJSONObject:device.name options:NSJSONWritingFragmentsAllowed error:nil];
    const std::string gpuName(static_cast<const char*>(nameData.bytes),nameData.length);
    auto queue=[device newCommandQueue];unsigned samples=0;size_t pixels=0;
    // A complete 10-bit ramp plus alternating single-pixel chroma columns.
    // These are source code values, not a claim about the connected display.
    auto codeAt=[](unsigned x,unsigned y,unsigned component) {
        return component ? (((x+component)&1)?64u:960u) : (x+128*y)%1024;
    };
    unsigned rampCases=0,singlePixelCases=0;
    for (bool full:{false,true}) for (bool c444:{false,true}) {
        PWClient::HDRPresenter presenter;
        check(presenter.prepare(device,128,128,full,c444),"pixel buffer pool / packing pipeline");
        for (bool hdr:{true,false}) { @autoreleasepool {
            id<MTLTexture> planes[3];
            auto command=[queue commandBuffer];auto blit=[command blitCommandEncoder];
            for (unsigned p=0;p<3;++p) {
                const unsigned size=p&&!c444?64:128;
                auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Unorm width:size height:size mipmapped:NO];
                desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageShaderRead;
                planes[p]=[device newTextureWithDescriptor:desc];check(planes[p]!=nil,"input plane");
                const size_t row=256;
                auto buffer=[device newBufferWithLength:row*size options:MTLResourceStorageModeShared];
                check(buffer!=nil,"input upload");
                auto values=static_cast<uint16_t*>(buffer.contents);
                for (unsigned y=0;y<size;++y) for (unsigned x=0;x<size;++x)
                    values[y*(row/2)+x]=uint16_t((codeAt(x,y,p)*65535u+511u)/1023u);
                [blit copyFromBuffer:buffer sourceOffset:0 sourceBytesPerRow:row sourceBytesPerImage:row*size
                    sourceSize:MTLSizeMake(size,size,1) toTexture:planes[p] destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
            }
            [blit endEncoding];
            const std::array<uint8_t,24> masteringBytes={0x33,0xc2,0x86,0xc4};
            const std::array<uint8_t,4> lightBytes={0x03,0xe8,0x01,0x90};
            NSData* mastering=[NSData dataWithBytes:masteringBytes.data() length:masteringBytes.size()];
            NSData* light=[NSData dataWithBytes:lightBytes.data() length:lightBytes.size()];
            auto surface=presenter.encode(command,planes,2,hdr,mastering,light);check(bool(surface),"encode 10-bit surface");
            [command commit];[command waitUntilCompleted];
            check(command.status==MTLCommandBufferStatusCompleted,"GPU packing execution");
            check(CVPixelBufferLockBaseAddress(surface->image,kCVPixelBufferLock_ReadOnly)==kCVReturnSuccess,"readback lock");
            std::array<bool,1024> levels{};
            for (unsigned p=0;p<2;++p) {
                unsigned width=unsigned(CVPixelBufferGetWidthOfPlane(surface->image,p));
                unsigned height=unsigned(CVPixelBufferGetHeightOfPlane(surface->image,p));
                const auto base=static_cast<const uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(surface->image,p));
                const size_t row=CVPixelBufferGetBytesPerRowOfPlane(surface->image,p);
                for (unsigned y=0;y<height;++y) for (unsigned x=0;x<width;++x) for (unsigned c=0;c<(p?2:1);++c) {
                    const auto values=reinterpret_cast<const uint16_t*>(base+y*row);
                    unsigned component=p?c+1:0;
                    const unsigned value=values[x*(p?2:1)+c];
                    check(value==codeAt(x,y,component)*64u,"10-bit ramp or single-pixel chroma mismatch");
                    if (!p) levels[value>>6]=true;
                    ++pixels;
                }
            }
            CVPixelBufferUnlockBaseAddress(surface->image,kCVPixelBufferLock_ReadOnly);
            for (bool present:levels) check(present,"10-bit ramp lost a level");
            ++rampCases;
            if (c444) ++singlePixelCases;
            check(presenter.makeSample(surface),"sample format construction");
            check(!presenter.makeSample(surface),"duplicate sample must fail");
            auto transfer=CVBufferCopyAttachment(surface->image,kCVImageBufferTransferFunctionKey,nullptr);
            check(transfer && CFEqual(transfer,hdr?kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ:kCVImageBufferTransferFunction_ITU_R_709_2),"PQ/SDR transfer tag");
            CFRelease(transfer);
            const OSType expected=c444?(full?kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange):
                (full?kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
            check(CMFormatDescriptionGetMediaSubType(surface->format)==expected,"sample pixel format or range");
            for (auto key:{kCVImageBufferMasteringDisplayColorVolumeKey,kCVImageBufferContentLightLevelInfoKey}) {
                auto value=CVBufferCopyAttachment(surface->image,key,nullptr);
                check(hdr?bool(value):!value,"HDR static metadata leaked into SDR or was omitted");
                if (value) { check(CFEqual(value,(__bridge CFDataRef)(key==kCVImageBufferMasteringDisplayColorVolumeKey?mastering:light)),"HDR static metadata changed"); CFRelease(value); }
            }
            check(!presenter.encode(command,planes,1,true,nil,nil),"PQ with non-BT.2020 primaries must fail");
            check(!presenter.encode(command,planes,3,false,nil,nil),"unknown colorspace must fail");
            if (hdr) {
                std::vector<std::shared_ptr<PWClient::VideoSurface>> retained;
                for (unsigned i=0;i<2;++i) {
                    auto next=[queue commandBuffer];auto extra=presenter.encode(next,planes,2,true,mastering,light);
                    check(bool(extra),"three-surface pool capacity");
                    [next commit];[next waitUntilCompleted];retained.push_back(extra);
                }
                auto next=[queue commandBuffer];
                check(!presenter.encode(next,planes,2,true,mastering,light),"presentation pool grew beyond three retained surfaces");
                retained.clear();
                auto recovered=presenter.encode(next,planes,2,false,nil,nil);
                check(bool(recovered),"presentation pool failed to recover after backpressure");
                [next commit];[next waitUntilCompleted];
                auto stale=CVBufferCopyAttachment(recovered->image,kCVImageBufferMasteringDisplayColorVolumeKey,nullptr);
                check(!stale,"recycled SDR surface retained HDR mastering metadata");
            }
            ++samples;
        }}
    }
    std::cout<<"{\"gpu_available\":true,\"gpu_name\":"<<gpuName<<",\"samples_checked\":"<<samples<<",\"packed_samples_checked\":"<<pixels<<",\"preserved_10bit_levels_per_case\":1024,\"ramp_cases\":"<<rampCases<<",\"single_pixel_444_cases\":"<<singlePixelCases<<",\"pool_limit_verified\":true,\"pool_recovery_verified\":true,\"static_hdr_metadata_verified\":true,\"physical_hdr_display_tested\":false}\n";
    return 0;
} catch(const std::exception& e) { std::cerr<<e.what()<<"\n";return 1; } }}
