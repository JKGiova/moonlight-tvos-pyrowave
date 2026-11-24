#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build a temporary offline A12 diagnostic in the existing signed tvOS project.

Managed sources are restored even when compilation fails. No target or project is
added. The artifact is explicit diagnostics; reinstall the normal app after use.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from prepare_client import DEFAULT_CLIENT, ROOT, prepare


def device_source(source):
    start = source.index('struct HostDecoderDevice {')
    end = source.index('void fullDecoderBenchmark', start)
    source = source[:start] + '''struct HostDecoderDevice {
    std::unique_ptr<pyrowave_device_opaque, decltype(&pyrowave_device_destroy)>
        value{nullptr, &pyrowave_device_destroy};
    HostDecoderDevice(id<MTLDevice> metal, id<MTLComputePipelineState>) {
        pyrowave_device_create_info info{};
        info.mtl_device=(__bridge void*)metal;
        pyrowave_device created=nullptr;
        PWTest::require(pw_decoder_device_create(&info,false,&created)==PYROWAVE_SUCCESS,
                        "physical production decoder factory");
        value.reset(created);
        PWTest::require(std::string(pw_decoder_backend_name(created))=="metal-portable-apple5",
                        "this diagnostic requires the production Apple5 backend");
    }
};
''' + source[end:]
    source = source.replace('host-lab-offscreen-split-serial', 'production-device-offscreen-split-serial')
    source = source.replace('\\"physical_apple_tv_tested\\":false', '\\"physical_apple_tv_tested\\":true')
    return source


def bridge(run_id, iterations, warmup):
    return r'''
// Temporary diagnostic, removed from the managed source after compilation.
#define main PWOfflineBenchmarkMain
#include "PWOfflineBenchmark.cpp"
#undef main
extern "C" void PWRunOfflineDeviceBenchmark(void) {
    @autoreleasepool {
        NSString* directory=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
        NSString* base=[directory stringByAppendingPathComponent:@"RUN_ID"];
        NSString* metrics=[base stringByAppendingString:@".json"];
        NSString* errors=[base stringByAppendingString:@".log"];
        NSString* status=[base stringByAppendingString:@".status.json"];
        std::ofstream output(metrics.fileSystemRepresentation), log(errors.fileSystemRepresentation);
        auto previousOut=std::cout.rdbuf(output.rdbuf());
        auto previousErr=std::cerr.rdbuf(log.rdbuf());
        const char* values[]={"device-benchmark","--iterations","ITERATIONS","--warmup","WARMUP"};
        const NSInteger thermalBefore=NSProcessInfo.processInfo.thermalState;
        int result=PWOfflineBenchmarkMain(5,const_cast<char**>(values));
        output.flush(); log.flush();
        std::cout.rdbuf(previousOut); std::cerr.rdbuf(previousErr);
        NSDictionary* summary=@{@"exit_code":@(result),@"thermal_before":@(thermalBefore),
            @"thermal_after":@(NSProcessInfo.processInfo.thermalState),@"run_id":@"RUN_ID"};
        [[NSJSONSerialization dataWithJSONObject:summary options:0 error:nil] writeToFile:status atomically:YES];
        NSLog(@"Offline A12 diagnostic finished with status %d",result);
    }
}
'''.replace('RUN_ID',run_id).replace('ITERATIONS',str(iterations)).replace('WARMUP',str(warmup))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device-name',required=True)
    parser.add_argument('--baseline',action='store_true',help='Use pre-batching Apple5 shader and decoder from 15df554.')
    parser.add_argument('--iterations',type=int,default=100)
    parser.add_argument('--warmup',type=int,default=20)
    args=parser.parse_args()
    if not 1<=args.iterations<=10000 or not 0<=args.warmup<=10000:
        parser.error('Invalid sample count')
    client=prepare(DEFAULT_CLIENT)
    run_id='pyrowave-offline-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder=ROOT/'benchmarks/local'/run_id
    folder.mkdir(parents=True)
    artifact=ROOT/'build/DerivedDataClient/Release-appletvos-build/Build/Products/Release-appletvos/Moonlight TV.app'
    if artifact.exists():
        shutil.copytree(artifact,folder/'previous.app')
    runtime=client/'PyroWaveRuntime'
    files={client/'Limelight/AppDelegate.m':None,runtime/'apple/PyroWaveVideoRenderer.mm':None,
           runtime/'apple/PWOfflineBenchmark.cpp':None,runtime/'apple/dequant_fixture.hpp':None}
    if args.baseline:
        files.update({runtime/'metal/pyrowave_decoder.mm':None,
                      runtime/'apple/PyroWaveApple5Source.h':None,
                      runtime/'metal/shaders/pyrowave_apple5_msl.h':None})
    lock=client.parent/('.'+client.name+'.prepare.lock')
    with lock.open('a') as held:
        fcntl.flock(held,fcntl.LOCK_EX)
        originals={p:p.read_bytes() if p.exists() else None for p in files}
        try:
            delegate=next(p for p in files if p.name=='AppDelegate.m')
            text=originals[delegate].decode().replace('@implementation AppDelegate','extern void PWRunOfflineDeviceBenchmark(void);\n\n@implementation AppDelegate')
            anchor='    return YES;\n}'
            if text.count(anchor)!=1:
                raise RuntimeError('App launch hook changed; refusing an ambiguous diagnostic injection')
            text=text.replace(anchor,'''    if ([NSProcessInfo.processInfo.arguments containsObject:@"-PyroWaveOfflineBenchmark"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            PWRunOfflineDeviceBenchmark();
        });
    }
    return YES;
}''',1)
            delegate.write_text(text)
            renderer=runtime/'apple/PyroWaveVideoRenderer.mm'
            renderer.write_bytes(originals[renderer]+bridge(run_id,args.iterations,args.warmup).encode())
            (runtime/'apple/PWOfflineBenchmark.cpp').write_text(device_source((ROOT/'tools/benchmark_client.cpp').read_text()))
            shutil.copy2(ROOT/'tests/dequant_fixture.hpp',runtime/'apple/dequant_fixture.hpp')
            if args.baseline:
                (runtime/'metal/pyrowave_decoder.mm').write_bytes((ROOT/'third_party/pyrowave/metal/pyrowave_decoder.mm').read_bytes())
                header=subprocess.check_output(['git','show','15df554:native/apple/PyroWaveApple5Source.h'],cwd=ROOT)
                for p in [runtime/'apple/PyroWaveApple5Source.h',runtime/'metal/shaders/pyrowave_apple5_msl.h']:
                    p.write_bytes(header)
            metadata={'run_id':run_id,'baseline':args.baseline,'iterations':args.iterations,'warmup':args.warmup,
                      'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                      'diagnostic_source_sha256':hashlib.sha256((runtime/'apple/PWOfflineBenchmark.cpp').read_bytes()).hexdigest(),
                      'decoder_source_sha256':hashlib.sha256((runtime/'metal/pyrowave_decoder.mm').read_bytes()).hexdigest(),
                      'shader_header_sha256':hashlib.sha256((runtime/'apple/PyroWaveApple5Source.h').read_bytes()).hexdigest()}
            (folder/'manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
            with (folder/'build.log').open('w') as log:
                subprocess.run(['xcodebuild','-project',str(client/'Moonlight.xcodeproj'),'-scheme','Moonlight TV',
                    '-configuration','Release','-sdk','appletvos','-destination','platform=tvOS,name='+args.device_name,
                    '-derivedDataPath',str(ROOT/'build/DerivedDataClient/Release-appletvos-build'),
                    '-allowProvisioningUpdates','build'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
            shutil.copytree(artifact,folder/'diagnostic.app')
        finally:
            for p,contents in originals.items():
                if contents is None: p.unlink(missing_ok=True)
                else: p.write_bytes(contents)
    print(folder)


if __name__=='__main__':
    main()
