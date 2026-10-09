#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a reviewable tvOS client from pristine pins plus selective patches."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from prepare_metal import prepare_metal
ROOT = Path(__file__).resolve().parents[1]
PINS = {'app/Moonlight': '02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a',
        'app/Moonlight/moonlight-common/moonlight-common-c': 'f900dd4767759c7b9d0e93bcea666b55c69ea62f',
        'third_party/pyrowave': '186f0393b77f7755953b5ecde994bb1cec2e4155'}


def inputs():
    files = [Path(__file__), ROOT/'tools/prepare_metal.py', ROOT/'tools/embed_apple5_shader.py']
    for directory in ['native/apple', 'native/client', 'native/protocol', 'third_party/pyrowave/metal', 'integration/patches']:
        files += [p for p in (ROOT/directory).rglob('*') if p.is_file()]
    return sorted(files)


def prepare(destination: Path) -> Path:
    destination = destination.resolve()
    # Generated checkouts stay within ignored build/. Never overwrite an app,
    # a source submodule, or a user-owned directory.
    if not destination.is_relative_to(ROOT/'build') or destination == ROOT/'build':
        raise RuntimeError('Prepared client must be a new directory below build/.')
    # A matching cache record never excuses drift of the upstream checkouts.
    # Verify before returning an existing directory, including nested gitlinks.
    for path, pin in PINS.items():
        revision = subprocess.check_output(['git', '-C', str(ROOT/path), 'rev-parse', 'HEAD'], text=True).strip()
        if revision != pin:
            raise RuntimeError('Initialize the exact upstream pins with tools/bootstrap.py first.')
    nested = subprocess.check_output(['git','-C',str(ROOT/'app/Moonlight'),
                                     'submodule','status','--recursive'],text=True)
    if any(line and line[0] != ' ' for line in nested.splitlines()):
        raise RuntimeError('Nested Moonlight dependencies differ or are not initialized; run tools/bootstrap.py.')
    for path in PINS:
        subprocess.run(['git','-C',str(ROOT/path),'-c','diff.ignoreSubmodules=none',
                        'diff','--quiet','HEAD','--'],check=True)
    digest = hashlib.sha256()
    for path in inputs():
        digest.update(str(path.relative_to(ROOT)).encode()); digest.update(path.read_bytes())
    manifest = {'pins': PINS, 'integration_sha256': digest.hexdigest()}
    if destination.exists():
        record = destination/'pyrowave-preparation.json'
        if record.is_file() and json.loads(record.read_text()) == manifest:
            return destination
        raise RuntimeError('Prepared directory exists with different inputs. Choose a fresh --client-dir; existing edits are preserved.')
    shutil.copytree(ROOT/'app/Moonlight', destination, ignore=shutil.ignore_patterns('.git', 'DerivedData', '__pycache__'))
    try:
        # Local metadata makes git apply independent of the enclosing repository.
        subprocess.run(['git','init','--quiet',str(destination)],check=True)
        for patch, directory in [('moonlight-ios.patch', destination),
                                  ('moonlight-cleanup.patch', destination),
                                  ('moonlight-common-c.patch', destination/'moonlight-common/moonlight-common-c'),
                                  ('common-c-cleanup.patch', destination/'moonlight-common/moonlight-common-c')]:
            command = ['git','-C',str(destination),'apply','--unsafe-paths','--directory='+str(directory),str(ROOT/'integration/patches'/patch)]
            subprocess.run([*command[:4], '--check', *command[4:]],check=True)
            subprocess.run(command,check=True)
        runtime = destination/'PyroWaveRuntime'
        for name in ['apple','client','protocol']:
            shutil.copytree(ROOT/'native'/name, runtime/name)
        prepare_metal(runtime/'metal')
        shutil.copy2(ROOT/'native/client/bitstream_identity.h',destination/'moonlight-common/moonlight-common-c/src/bitstream_identity.h')
        (destination/'pyrowave-preparation.json').write_text(json.dumps(manifest,indent=2)+'\n')
    except Exception:
        # A failed copy is deliberately retained for diagnosis; never reused as a success.
        raise
    return destination


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-dir', type=Path, default=ROOT/'build/client/Moonlight')
    try:
        print(prepare(parser.parse_args().client_dir))
    except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr); raise SystemExit(1)
