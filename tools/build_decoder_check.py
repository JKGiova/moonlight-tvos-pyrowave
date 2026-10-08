#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build/run shader and full-decoder correctness checks, without an encoder."""
import argparse
import platform
import subprocess
import sys
from pathlib import Path
from prepare_metal import prepare_metal
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        raise RuntimeError('Metal correctness checks require macOS/Xcode; portable fixture tests run on Linux/Windows.')
    metal = prepare_metal()
    output = ROOT/'build/metal/check-apple5'
    files = [metal/name for name in ['pyrowave_common.mm', 'pyrowave_decoder.mm', 'pyrowave_bitstream.cpp']]
    files += [ROOT/'native/protocol/pyrowaveframing.cpp', ROOT/'tools/check_apple5_decoder.mm']
    subprocess.run(['xcrun', 'clang++', '-std=c++17', '-O2', '-fobjc-arc',
                    *['-I'+str(path) for path in [metal, ROOT/'native/apple', ROOT/'tests', ROOT/'native/protocol']],
                    *map(str, files), '-framework', 'Metal', '-framework', 'Foundation', '-framework', 'IOSurface',
                    '-o', str(output)], check=True)
    if args.run:
        subprocess.run([str(output)], check=True)
    else:
        print(output)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr); raise SystemExit(1)
