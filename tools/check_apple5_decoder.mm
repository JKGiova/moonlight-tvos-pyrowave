// SPDX-License-Identifier: MIT
// Run the actual portable dequantizer against known coefficient records. A Mac
// GPU test is separate from live Apple-family admission and tvOS qualification.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "PyroWaveApple5Source.h"
#include "shaders/pyrowave_msl.h"
#include "dequant_fixture.hpp"
#include <algorithm>
#include <iostream>

static id<MTLLibrary> library(id<MTLDevice> device,const char* source) {
    NSError* error=nil;
    auto options=[MTLCompileOptions new];options.languageVersion=MTLLanguageVersion2_2;
    auto result=[device newLibraryWithSource:@(source) options:options error:&error];
    if (!result) throw std::runtime_error(error.localizedDescription.UTF8String ?: "Metal library failed");
    return result;
}
static id<MTLComputePipelineState> pipeline(id<MTLDevice> device,id<MTLLibrary> source,NSString* name,unsigned threads,int dcShift=-1) {
    NSError* error=nil;
    id<MTLFunction> function;
    if (dcShift<0) function=[source newFunctionWithName:name];
    else {
        auto constants=[MTLFunctionConstantValues new];bool shift=dcShift!=0;
        [constants setConstantValue:&shift type:MTLDataTypeBool atIndex:0];
        function=[source newFunctionWithName:name constantValues:constants error:&error];
    }
    if (!function) throw std::runtime_error(error.localizedDescription.UTF8String ?: "Metal function missing");
    auto state=[device newComputePipelineStateWithFunction:function error:&error];
    if (!state) throw std::runtime_error(error.localizedDescription.UTF8String ?: "Metal pipeline failed");
    PWTest::require(state.maxTotalThreadsPerThreadgroup>=threads,"pipeline thread limit");
    PWTest::require(state.staticThreadgroupMemoryLength<=device.maxThreadgroupMemoryLength,"pipeline shared memory limit");
    return state;
}
static double verify(id<MTLDevice> device,id<MTLComputePipelineState> state,const PWTest::DequantFixture& fixture) {
    PyroWave::BitstreamParser parser;PWTest::parseFixture(fixture,parser);
    const auto& words=parser.payload();const auto& offsets=parser.dequant_offsets();
    // Match the pinned decoder's padded upload contract, with deterministic zero padding.
    auto payload=[device newBufferWithLength:words.size()*4+16 options:MTLResourceStorageModeShared];
    auto lookup=[device newBufferWithBytes:offsets.data() length:offsets.size()*4 options:MTLResourceStorageModeShared];
    auto readback=[device newBufferWithLength:64*64*sizeof(float) options:MTLResourceStorageModeShared];
    PWTest::require(payload&&lookup&&readback,"test buffer allocation");
    std::memset(payload.contents,0,payload.length);std::memcpy(payload.contents,words.data(),words.size()*4);
    auto descriptor=[MTLTextureDescriptor new];descriptor.textureType=MTLTextureType2DArray;
    descriptor.pixelFormat=MTLPixelFormatR32Float;descriptor.width=64;descriptor.height=64;descriptor.arrayLength=2;
    descriptor.storageMode=MTLStorageModePrivate;descriptor.usage=MTLTextureUsageShaderWrite;
    auto output=[device newTextureWithDescriptor:descriptor];auto queue=[device newCommandQueue];
    PWTest::require(output&&queue,"test texture/queue allocation");
    auto command=[queue commandBuffer];auto compute=[command computeCommandEncoder];
    PWTest::require(command&&compute,"test command allocation");
    struct alignas(8) Registers {int resolution[2];int layer,offset,stride;} registers{{64,64},1,fixture.blockOffset,2};
    [compute setComputePipelineState:state];[compute setBuffer:payload offset:0 atIndex:0];
    [compute setBytes:&registers length:sizeof(registers) atIndex:1];[compute setBuffer:lookup offset:0 atIndex:2];
    [compute setTexture:output atIndex:0];
    [compute dispatchThreadgroups:MTLSizeMake(2,2,1) threadsPerThreadgroup:MTLSizeMake(128,1,1)];[compute endEncoding];
    auto blit=[command blitCommandEncoder];PWTest::require(blit!=nil,"test blit allocation");
    [blit copyFromTexture:output sourceSlice:1 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(64,64,1)
                toBuffer:readback destinationOffset:0 destinationBytesPerRow:64*sizeof(float) destinationBytesPerImage:64*64*sizeof(float)];
    [blit endEncoding];[command commit];[command waitUntilCompleted];
    if (command.status!=MTLCommandBufferStatusCompleted) throw std::runtime_error(command.error.localizedDescription.UTF8String ?: "test GPU command failed");
    const auto values=static_cast<const float*>(readback.contents);double maximum=0;
    for (size_t i=0;i<fixture.expected.size();++i) {
        const double delta=std::abs(double(values[i])-fixture.expected[i]);
        if (!std::isfinite(values[i]) || delta>1e-5*std::abs(double(fixture.expected[i]))+1e-4)
            throw std::runtime_error("dequant mismatch at coefficient "+std::to_string(i));
        maximum=std::max(maximum,delta);
    }
    return maximum;
}
int main() {
    @autoreleasepool {try {
        auto device=MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cout<<"{\"device_available\":false,\"gpu_execution_tested\":false,\"reason\":\"no_metal_device\",\"auto_qualified\":false}\n";return 0;
        }
        auto portable=pipeline(device,library(device,wavelet_dequant_apple5_msl_source),@"pyrowave_wavelet_dequant",128);
        // Compile the actual unchanged iDWT in every precision and DC mode under
        // the same MSL 2.2 ceiling used by the portable runtime.
        for (const char* source:{PyroWave::idwt_fp16_msl_source,PyroWave::idwt_fp16_storage_msl_source,PyroWave::idwt_msl_source}) {
            auto compiled=library(device,source);
            for (int shift=0;shift<2;++shift) pipeline(device,compiled,@"pyrowave_idwt",64,shift);
        }
        id<MTLComputePipelineState> native=nil;
        if ([device supportsFamily:MTLGPUFamilyApple7]) {
            native=pipeline(device,library(device,PyroWave::wavelet_dequant_msl_source),@"pyrowave_wavelet_dequant",128);
            PWTest::require(native.threadExecutionWidth==32,"native SIMD width");
        }
        double maxError=0;
        for (unsigned seed=0;seed<8;++seed) {
            PWTest::DequantFixture fixture;PWTest::makeFixture(fixture,seed);
            maxError=std::max(maxError,verify(device,portable,fixture));
            if (native) verify(device,native,fixture);
        }
        std::cout<<"{\"device_available\":true,\"portable_pipeline_compiled\":true,\"idwt_pipelines_compiled\":6,\"gpu_execution_tested\":true,\"fixture_cases\":8,\"coefficients_checked\":32768,\"max_absolute_error\":"<<maxError
                 <<",\"native_reference_tested\":"<<(native?"true":"false")<<",\"physical_apple_tv_tested\":false,\"auto_qualified\":false}\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;} }
}
