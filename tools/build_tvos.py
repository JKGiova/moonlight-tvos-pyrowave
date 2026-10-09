#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the integrated Moonlight TV client, or the pristine baseline explicitly."""
import argparse
from datetime import datetime, timezone
import platform
import subprocess
import sys
from pathlib import Path
from prepare_client import prepare
from xcode_diagnostics import capture
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration',choices=['Debug','Release'],default='Debug')
    parser.add_argument('--sdk',choices=['appletvsimulator','appletvos'],default='appletvsimulator')
    parser.add_argument('--action',choices=['build','analyze'],default='build')
    parser.add_argument('--baseline',action='store_true',help='Build pristine Moonlight without the integration patches.')
    parser.add_argument('--client-dir',type=Path,default=ROOT/'build/client/Moonlight')
    args=parser.parse_args()
    if platform.system()!='Darwin':raise RuntimeError('tvOS compilation requires Mac/Xcode.')
    source=ROOT/'app/Moonlight'
    subprocess.run(['git','submodule','update','--init','--recursive'],check=True,cwd=ROOT)
    if subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()!='02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a':
        raise RuntimeError('Moonlight baseline revision differs from the reviewed pin.')
    if not args.baseline:
        source=prepare(args.client_dir)
    destination='generic/platform=tvOS Simulator' if args.sdk=='appletvsimulator' else 'generic/platform=tvOS'
    label=f'{args.configuration}-{args.sdk}-{args.action}'
    report=ROOT/'build/xcode'/label/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    capture(['xcodebuild','-project',str(source/'Moonlight.xcodeproj'),'-scheme','Moonlight TV',
                    '-configuration',args.configuration,'-sdk',args.sdk,'-destination',destination,
                    '-derivedDataPath',str(ROOT/'build'/('DerivedDataBaseline' if args.baseline else 'DerivedDataClient')/label),
                    '-resultBundlePath',str(report/'result.xcresult'),
                    'CODE_SIGNING_ALLOWED=NO',args.action],report)
    print(f'Unsigned client {args.action} completed. Physical installation needs your local team/bundle signing configuration in Xcode.')
if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr);raise SystemExit(1)
