// SPDX-License-Identifier: GPL-3.0-or-later
// Execute the live presenter offscreen. This checks color and orientation,
// not CAMetalLayer/display timing or physical Apple TV support.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "PyroWavePresenterSource.h"
#include "color_conversion.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <iostream>
#include <stdexcept>

namespace {
constexpr unsigned Width=16, Height=8, RowBytes=256;
using Color=std::array<uint8_t,3>;
struct Result { unsigned cases=0, pixels=0, maxError=0; };

void require(bool value,const char* message) {
    if (!value) throw std::runtime_error(message);
}

void verify(id<MTLDevice> device,id<MTLCommandQueue> queue,id<MTLRenderPipelineState> pipeline,
            int space,bool full,Color yuv,Color rgb,bool orientation,Result& result) {
    @autoreleasepool {
        auto command=[queue commandBuffer];
        auto upload=[command blitCommandEncoder];
        require(command && upload,"presenter upload command allocation");
        id<MTLTexture> planes[3];
        for (unsigned p=0;p<3;++p) {
            const unsigned width=Width/(p?2:1), height=Height/(p?2:1);
            auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                width:width height:height mipmapped:NO];
            descriptor.storageMode=MTLStorageModePrivate;
            descriptor.usage=MTLTextureUsageShaderRead;
            planes[p]=[device newTextureWithDescriptor:descriptor];
            auto staging=[device newBufferWithLength:RowBytes*height options:MTLResourceStorageModeShared];
            require(planes[p] && staging,"presenter source allocation");
            std::memset(staging.contents,0,staging.length);
            auto data=static_cast<uint8_t*>(staging.contents);
            for (unsigned y=0;y<height;++y) for (unsigned x=0;x<width;++x)
                data[y*RowBytes+x]=orientation && p==0 ? ((x<Width/2 && y<Height/2) ? 235 : 16) : yuv[p];
            [upload copyFromBuffer:staging sourceOffset:0 sourceBytesPerRow:RowBytes sourceBytesPerImage:RowBytes*height
                sourceSize:MTLSizeMake(width,height,1) toTexture:planes[p] destinationSlice:0 destinationLevel:0
                destinationOrigin:MTLOriginMake(0,0,0)];
        }
        [upload endEncoding];
        auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:Width height:Height mipmapped:NO];
        descriptor.storageMode=MTLStorageModePrivate; descriptor.usage=MTLTextureUsageRenderTarget;
        auto output=[device newTextureWithDescriptor:descriptor];
        auto readback=[device newBufferWithLength:RowBytes*Height options:MTLResourceStorageModeShared];
        require(output && readback,"presenter output allocation");
        auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=output;
        pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;
        pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        auto render=[command renderCommandEncoderWithDescriptor:pass];
        require(render!=nil,"presenter render command allocation");
        const auto conversion=PWClient::colorConversion(space,full);
        [render setRenderPipelineState:pipeline];
        for (unsigned p=0;p<3;++p) [render setFragmentTexture:planes[p] atIndex:p];
        [render setFragmentBytes:&conversion length:sizeof(conversion) atIndex:0];
        [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [render endEncoding];
        auto blit=[command blitCommandEncoder]; require(blit!=nil,"presenter readback allocation");
        [blit copyFromTexture:output sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
            sourceSize:MTLSizeMake(Width,Height,1) toBuffer:readback destinationOffset:0
            destinationBytesPerRow:RowBytes destinationBytesPerImage:RowBytes*Height];
        [blit endEncoding]; [command commit]; [command waitUntilCompleted];
        if (command.status!=MTLCommandBufferStatusCompleted)
            throw std::runtime_error(command.error.localizedDescription.UTF8String ?: "presenter GPU command failed");
        const auto pixels=static_cast<const uint8_t*>(readback.contents);
        for (unsigned y=0;y<Height;++y) for (unsigned x=0;x<Width;++x) {
            const uint8_t* actual=pixels+y*RowBytes+x*4;
            const unsigned gray=x<Width/2 && y<Height/2 ? 255 : 0;
            for (unsigned c=0;c<3;++c) {
                const unsigned expected=orientation ? gray : rgb[2-c]; // BGRA storage.
                const unsigned error=unsigned(std::abs(int(actual[c])-int(expected)));
                require(error<=2,"presenter color/orientation mismatch (>2 code values)");
                result.maxError=std::max(result.maxError,error);
            }
            require(actual[3]==255,"presenter alpha mismatch"); ++result.pixels;
        }
        ++result.cases;
    }
}
}

int main() {
    @autoreleasepool { try {
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cout<<"{\"device_available\":false,\"presenter_pipeline_compiled\":false,\"reason\":\"no_metal_device\",\"gpu_execution_tested\":false,\"auto_qualified\":false}\n";
            return 0;
        }
        NSError* error=nil;
        auto library=[device newLibraryWithSource:[NSString stringWithUTF8String:PWClient::PresenterSource] options:nil error:&error];
        if (!library) throw std::runtime_error(error.localizedDescription.UTF8String ?: "presenter library failed");
        auto descriptor=[MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction=[library newFunctionWithName:@"pw_vertex"];
        descriptor.fragmentFunction=[library newFunctionWithName:@"pw_fragment"];
        descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        auto pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:&error];
        if (!pipeline) throw std::runtime_error(error.localizedDescription.UTF8String ?: "presenter pipeline failed");
        auto queue=[device newCommandQueue]; require(queue!=nil,"presenter queue allocation");
        // Independently specified black/white/gray/red/green/blue vectors.
        // A two-code-value tolerance accounts for rounded 8-bit YCbCr inputs.
        constexpr Color reference[]={{0,0,0},{255,255,255},{128,128,128},{255,0,0},{0,255,0},{0,0,255}};
        constexpr Color limited601[]={{16,128,128},{235,128,128},{126,128,128},{81,90,240},{145,54,34},{41,240,110}};
        constexpr Color limited709[]={{16,128,128},{235,128,128},{126,128,128},{63,102,240},{173,42,26},{32,240,118}};
        constexpr Color full601[]={{0,128,128},{255,128,128},{128,128,128},{76,85,255},{150,44,21},{29,255,107}};
        constexpr Color full709[]={{0,128,128},{255,128,128},{128,128,128},{54,99,255},{182,30,12},{18,255,116}};
        Result result;
        for (int space:{0,1}) for (bool full:{false,true}) {
            const Color* inputs=full ? (space ? full709 : full601) : (space ? limited709 : limited601);
            for (unsigned i=0;i<6;++i) verify(device,queue,pipeline,space,full,inputs[i],reference[i],false,result);
        }
        verify(device,queue,pipeline,1,false,{16,128,128},{0,0,0},true,result);
        std::cout<<"{\"device_available\":true,\"presenter_pipeline_compiled\":true,\"gpu_execution_tested\":true,\"color_orientation_cases\":"
                 <<result.cases<<",\"pixels_checked\":"<<result.pixels<<",\"max_channel_error\":"<<result.maxError
                 <<",\"channel_tolerance\":2,\"physical_apple_tv_tested\":false,\"display_presentation_tested\":false,\"auto_qualified\":false}\n";
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; } }
}
