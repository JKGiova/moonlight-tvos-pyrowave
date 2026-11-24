#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a reviewable tvOS client from pristine pins plus selective patches."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from prepare_metal import prepare_metal
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CLIENT = ROOT/'build/client/Moonlight-Clean-Release'
PROJECT = 'Moonlight.xcodeproj/project.pbxproj'
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
    if not destination.is_relative_to(ROOT/'build') or destination == ROOT/'build':
        raise RuntimeError('Prepared client must be below build/.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Serialize preparation from Xcode, the CLI and CI for this checkout.
    with (destination.parent / ('.' + destination.name + '.prepare.lock')).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return prepare_locked(destination)


def file_hash(path: Path):
    if path.is_symlink():
        raise RuntimeError(f'Generated file is a symbolic link: {path}')
    if not path.exists():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record_generation(destination: Path, manifest: dict):
    manifest = dict(manifest)
    manifest['files'] = {
        path.relative_to(destination).as_posix(): file_hash(path)
        for path in sorted(destination.rglob('*'))
        if '.git' not in path.relative_to(destination).parts
        and path.is_file() and path.name != 'pyrowave-preparation.json'
    }
    manifest['project_base'] = (destination/PROJECT).read_text()
    return manifest


def update_client(destination: Path, generated: Path, previous: dict, manifest: dict):
    """Plan all changes before writing, preserve local edits, roll back I/O failures."""
    destination = destination.resolve()
    generated = generated.resolve()
    if 'files' not in previous:
        # Older generated checkouts recorded only the input digest. Adopt only
        # when sources match and project differences are local signing settings.
        signing = re.compile(
            r'^.*(?:DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE|'
            r'CURRENT_PROJECT_VERSION|PROVISIONING_PROFILE_SPECIFIER|CODE_SIGN_IDENTITY)'
            r'\s*=.*\n', re.MULTILINE)
        for name, expected in manifest['files'].items():
            local = destination/name
            matches = file_hash(local) == expected
            if name == PROJECT and local.is_file():
                matches = signing.sub('', local.read_text()) == signing.sub('', manifest['project_base'])
            if not matches:
                raise RuntimeError(
                    f'Legacy checkout has no baseline and differs in {name}; '
                    'reconcile this file with the repository before retrying. Files preserved.')
        previous = manifest
    changes = {}
    for name in sorted(previous['files'].keys() | manifest['files'].keys()):
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or '.git' in relative.parts:
            raise RuntimeError('Invalid path in preparation manifest.')
        local = destination/relative
        if local.parent.resolve() != local.parent:
            raise RuntimeError(f'Symbolic link in generated path: {name}')
        base_hash = previous['files'].get(name)
        new_hash = manifest['files'].get(name)
        local_hash = file_hash(local)
        if new_hash == base_hash or local_hash == new_hash:
            continue
        if local_hash == base_hash:
            changes[name] = (generated/relative).read_bytes() if new_hash else None
        elif name == PROJECT and base_hash and new_hash and local_hash:
            base = generated/'project-base.pbxproj'
            base.write_text(previous['project_base'])
            merged = subprocess.run(
                ['git', 'merge-file', '-p', str(local), str(base), str(generated/relative)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if merged.returncode:
                raise RuntimeError(f'Conflicting local changes in {name}; no files updated.')
            changes[name] = merged.stdout
        else:
            raise RuntimeError(f'Conflicting local changes in {name}; no files updated.')

    record = 'pyrowave-preparation.json'
    changes[record] = (json.dumps(manifest, indent=2) + '\n').encode()
    originals = {}
    try:
        for name, contents in changes.items():
            target = destination/name
            originals[name] = (target.read_bytes(), stat.S_IMODE(target.stat().st_mode)) if target.exists() else None
            if contents is None:
                target.unlink()
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                pending = generated/'pending-write'
                pending.write_bytes(contents)
                mode_source = target if target.exists() else generated/name
                if mode_source.is_file():
                    shutil.copymode(mode_source, pending)
                os.replace(pending, target)
    except OSError:
        for name, original in originals.items():
            target = destination/name
            if original is None:
                target.unlink(missing_ok=True)
            else:
                contents, mode = original
                target.write_bytes(contents)
                target.chmod(mode)
        raise


def prepare_locked(destination: Path) -> Path:
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
    record = destination/'pyrowave-preparation.json'
    if destination.exists():
        if not record.is_file():
            raise RuntimeError('Existing directory has no preparation manifest; files preserved.')
        previous = json.loads(record.read_text())
        if all(previous.get(key) == value for key, value in manifest.items()) and 'files' in previous:
            return destination
        with tempfile.TemporaryDirectory(prefix='.client-update-', dir=ROOT/'build') as temporary:
            generated = Path(temporary)/'client'
            generate_client(generated)
            updated = record_generation(generated, manifest)
            # Register old, matching checkouts before their first source update.
            if 'files' not in previous and all(previous.get(key) == value for key, value in manifest.items()):
                record.write_text(json.dumps(updated, indent=2) + '\n')
            else:
                update_client(destination, generated, previous, updated)
        return destination
    generate_client(destination)
    record.write_text(json.dumps(record_generation(destination, manifest), indent=2) + '\n')
    return destination


def generate_client(destination: Path):
    shutil.copytree(ROOT/'app/Moonlight', destination, ignore=shutil.ignore_patterns('.git', 'DerivedData', '__pycache__'))
    # A local Git root keeps relative patch paths inside the generated client.
    subprocess.run(['git', 'init', '--quiet', str(destination)], check=True)
    common_c = 'moonlight-common/moonlight-common-c'
    patches = [
        ('moonlight-ios.patch', '.'),
        ('moonlight-cleanup.patch', '.'),
        ('moonlight-tvos-bitrate.patch', '.'),
        ('moonlight-pyrowave-scheduling.patch', '.'),
        ('moonlight-common-c.patch', common_c),
        ('common-c-cleanup.patch', common_c),
        ('common-c-bitrate.patch', common_c),
        ('moonlight-video-profiles.patch', '.'),
    ]
    for patch, directory in patches:
        patch_path = ROOT / 'integration/patches' / patch
        command = ['git', '-C', str(destination), 'apply']
        arguments = [str(patch_path)]
        if directory != '.':
            arguments.insert(0, f'--directory={directory}')
        subprocess.run([*command, '--check', *arguments], check=True)
        subprocess.run([*command, *arguments], check=True)

    runtime = destination / 'PyroWaveRuntime'
    for name in ['apple', 'client', 'protocol']:
        shutil.copytree(ROOT / 'native' / name, runtime / name)
    prepare_metal(runtime / 'metal')
    shutil.copy2(ROOT/'native/client/pyrowave_profiles.h',destination/common_c/'src/pyrowave_profiles.h')
    shutil.copy2(ROOT / 'native/client/bitstream_identity.h',
                 destination / common_c / 'src/bitstream_identity.h')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-dir', type=Path, default=DEFAULT_CLIENT)
    try:
        print(prepare(parser.parse_args().client_dir))
    except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr); raise SystemExit(1)
