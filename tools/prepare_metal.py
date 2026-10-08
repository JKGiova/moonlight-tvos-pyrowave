#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stage a pristine Metal pin plus the reviewed decoder-only Apple5 patch."""
import hashlib
import shutil
import subprocess
from pathlib import Path
from embed_apple5_shader import content, HEADER
ROOT = Path(__file__).resolve().parents[1]
PIN = '186f0393b77f7755953b5ecde994bb1cec2e4155'


def prepare_metal(destination=None):
    source = ROOT/'third_party/pyrowave'
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != PIN:
        raise RuntimeError('PyroWave dependency differs from the reviewed pin.')
    subprocess.run(['git', '-C', str(source), 'diff', '--quiet', 'HEAD', '--'], check=True)
    if HEADER.read_text() != content():
        raise RuntimeError('Apple5 embedded shader differs; run tools/embed_apple5_shader.py.')
    patch = ROOT/'integration/patches/pyrowave-metal-apple5.patch'
    api = ROOT/'native/apple/pyrowave_decoder_backend.h'
    digest = hashlib.sha256()
    for path in [*sorted((source/'metal').rglob('*')), patch, api, HEADER,
                 Path(__file__), ROOT/'tools/embed_apple5_shader.py']:
        if path.is_file():
            digest.update(str(path.relative_to(ROOT)).encode()); digest.update(path.read_bytes())
    fingerprint = digest.hexdigest()
    destination = (destination or ROOT/'build/metal'/('source-'+fingerprint[:16])).resolve()
    if not destination.is_relative_to(ROOT/'build') or destination == ROOT/'build':
        raise RuntimeError('Metal staging must stay below build/.')
    record = destination/'pw-source.sha256'
    if destination.exists():
        if record.is_file() and record.read_text().strip() == fingerprint:
            return destination
        raise RuntimeError('Metal staging directory already exists with different inputs.')
    shutil.copytree(source/'metal', destination)
    shutil.copy2(api, destination/api.name)
    shutil.copy2(HEADER, destination/'shaders/pyrowave_apple5_msl.h')
    command = ['git', 'apply', '--unsafe-paths', '--directory='+str(destination), str(patch)]
    subprocess.run([*command[:2], '--check', *command[2:]], cwd=ROOT, check=True)
    subprocess.run(command, cwd=ROOT, check=True)
    record.write_text(fingerprint+'\n')
    return destination


if __name__ == '__main__':
    print(prepare_metal())
