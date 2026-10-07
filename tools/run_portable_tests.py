#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile parser tests/validator with an available C++17 compiler, then run tests."""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize',action='store_true',help='ASan+UBSan; leak detection depends on the local sandbox.')
    args=parser.parse_args()
    compiler=os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++')
    if not compiler:raise RuntimeError('Install a C++17 compiler, or use the CMake project with your Windows toolchain.')
    directory=ROOT/'build/portable';directory.mkdir(parents=True,exist_ok=True)
    flags=['-std=c++17','-Wall','-Wextra','-Werror','-g']
    if args.sanitize:flags += ['-fsanitize=address,undefined','-fno-omit-frame-pointer']
    subprocess.run([compiler,*flags,'-I'+str(ROOT/'native/client'),str(ROOT/'tests/client_runtime_tests.cpp'),'-o',str(directory/'client-runtime-tests')],check=True)
    subprocess.run([str(directory/'client-runtime-tests')],check=True)
    for target,source in [('framing-tests','tests/framing_tests.cpp'),('framing-check','tools/framing_check.cpp')]:
        subprocess.run([compiler,*flags,'-I'+str(ROOT/'native/protocol'),str(ROOT/source),str(ROOT/'native/protocol/pyrowaveframing.cpp'),'-o',str(directory/target)],check=True)
    codec=ROOT/'third_party/pyrowave/metal'
    if not (codec/'pyrowave_bitstream.cpp').is_file():raise RuntimeError('Initialize third_party/pyrowave submodule first.')
    # Preserve upstream source without promoting its existing warnings to our errors.
    subprocess.run([compiler,*[flag for flag in flags if flag != '-Werror'],'-c',
                    str(codec/'pyrowave_bitstream.cpp'),'-o',str(directory/'codec-bitstream.o')],check=True)
    subprocess.run([compiler,*flags,'-I'+str(ROOT/'native/protocol'),'-I'+str(codec),
                    str(ROOT/'tests/codec_layout_tests.cpp'),str(ROOT/'native/protocol/pyrowaveframing.cpp'),
                    str(directory/'codec-bitstream.o'),'-o',str(directory/'codec-layout-tests')],check=True)
    subprocess.run([str(directory/'codec-layout-tests')],check=True)
    subprocess.run([str(directory/'framing-tests')],check=True)
    subprocess.run([sys.executable,'-m','unittest','discover','-s',str(ROOT/'tests'),'-p','test_*.py'],check=True,cwd=ROOT)
if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr);raise SystemExit(1)
