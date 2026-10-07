#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Initialize pinned upstream sources, retaining their original project/license layout."""
import json
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    subprocess.run(['git','submodule','sync','--recursive'],cwd=ROOT,check=True)
    subprocess.run(['git','submodule','update','--init','--recursive'],cwd=ROOT,check=True)
    lock=json.loads((ROOT/'configs/upstreams.lock.json').read_text())
    pins={item['name']:item['commit'] for item in lock['sources']}
    for path,name in [('app/Moonlight','moonlight-ios'),('third_party/pyrowave','pyrowave-metal')]:
        actual=subprocess.check_output(['git','-C',str(ROOT/path),'rev-parse','HEAD'],text=True).strip()
        if actual!=pins[name]:raise RuntimeError(f'{path}: checkout differs from the reviewed pin')
    common=ROOT/'app/Moonlight/moonlight-common/moonlight-common-c'
    actual=subprocess.check_output(['git','-C',str(common),'rev-parse','HEAD'],text=True).strip()
    if actual!=pins['moonlight-common-c-baseline']:raise RuntimeError('common-c differs from the reviewed baseline')
    print('Pinned Moonlight, common-c and native Metal sources are ready.')
if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr);raise SystemExit(1)
