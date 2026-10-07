#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the genuine upstream Moonlight TV baseline; PyroWave runtime is not wired yet."""
import argparse
import platform
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration',choices=['Debug','Release'],default='Debug')
    parser.add_argument('--sdk',choices=['appletvsimulator','appletvos'],default='appletvsimulator')
    args=parser.parse_args()
    if platform.system()!='Darwin':raise RuntimeError('tvOS compilation requires Mac/Xcode.')
    source=ROOT/'app/Moonlight'
    subprocess.run(['git','submodule','update','--init','--recursive','app/Moonlight'],check=True,cwd=ROOT)
    if subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()!='02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a':
        raise RuntimeError('Moonlight baseline revision differs from the reviewed pin.')
    destination='generic/platform=tvOS Simulator' if args.sdk=='appletvsimulator' else 'generic/platform=tvOS'
    subprocess.run(['xcodebuild','-project',str(source/'Moonlight.xcodeproj'),'-scheme','Moonlight TV',
                    '-configuration',args.configuration,'-sdk',args.sdk,'-destination',destination,
                    '-derivedDataPath',str(ROOT/'build/DerivedData'),'CODE_SIGNING_ALLOWED=NO','build'],check=True)
    print('Unsigned baseline built. Physical installation needs your local team/bundle signing configuration in Xcode.')
if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr);raise SystemExit(1)
