#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the pinned native Metal offline encoder/decoder without Granite/Vulkan."""
import platform
import subprocess
import sys
from pathlib import Path
from prepare_metal import prepare_metal
ROOT=Path(__file__).resolve().parents[1]
PIN='186f0393b77f7755953b5ecde994bb1cec2e4155'
def main():
    if platform.system()!='Darwin':
        raise RuntimeError('Native Metal requires macOS/Xcode. Linux/Windows can run portable tests and use an external Vulkan encoder.')
    source=ROOT/'third_party/pyrowave'
    revision=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    if revision!=PIN:raise RuntimeError('PyroWave dependency revision differs from the reviewed pin.')
    output=ROOT/'build/metal';output.mkdir(parents=True,exist_ok=True)
    metal=prepare_metal()
    files=[metal/name for name in ['pyrowave_common.mm','pyrowave_encoder.mm','pyrowave_decoder.mm','pyrowave_bitstream.cpp']]
    files += [source/'yuv4mpeg.cpp',ROOT/'native/protocol/pyrowaveframing.cpp',ROOT/'tools/pyrowave_video.mm']
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-fobjc-arc','-DPYROWAVE_EXPORT_SYMBOLS',
                    '-I'+str(metal),'-I'+str(source),'-I'+str(ROOT/'native/protocol'),
                    *map(str,files),'-framework','Metal','-framework','Foundation','-framework','IOSurface',
                    '-o',str(output/'pyrowave-video')],check=True)
    print(output/'pyrowave-video')
if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr);raise SystemExit(1)
