// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "PyroWavePresenterSource.h"
#include <iostream>

// Compile the actual live presenter source, even on a Metal GPU which cannot
// run the Apple7 PyroWave codec. This is a shader/pipeline compilation check,
// not numerical output or physical-device performance qualification.
int main() {
    @autoreleasepool {
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cout<<"{\"device_available\":false,\"presenter_pipeline_compiled\":false,\"reason\":\"no_metal_device\",\"gpu_execution_tested\":false}\n";
            return 0;
        }
        NSError* error=nil;
        id<MTLLibrary> library=[device newLibraryWithSource:[NSString stringWithUTF8String:PWClient::PresenterSource] options:nil error:&error];
        if (!library) { std::cerr<<error.localizedDescription.UTF8String<<'\n'; return 1; }
        auto descriptor=[MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction=[library newFunctionWithName:@"pw_vertex"];
        descriptor.fragmentFunction=[library newFunctionWithName:@"pw_fragment"];
        descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        if (!descriptor.vertexFunction || !descriptor.fragmentFunction || ![device newRenderPipelineStateWithDescriptor:descriptor error:&error]) {
            std::cerr<<(error.localizedDescription.UTF8String ?: "missing presenter function")<<'\n'; return 1;
        }
        std::cout<<"{\"device_available\":true,\"presenter_pipeline_compiled\":true,\"gpu_execution_tested\":false,\"auto_qualified\":false}\n";
        return 0;
    }
}
