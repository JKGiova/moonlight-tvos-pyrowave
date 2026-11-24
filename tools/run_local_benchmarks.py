#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run isolated CPU/Metal stage benchmarks and optional unsigned tvOS builds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=int, default=100)
    parser.add_argument('--warmup', type=int, default=20)
    parser.add_argument('--cpu-only', action='store_true')
    parser.add_argument('--builds', action='store_true', help='Build Debug and Release for simulator and device in the existing project.')
    parser.add_argument('--shader-source', type=Path)
    parser.add_argument('--framing-source', type=Path)
    parser.add_argument('--compare-framing', type=Path, help='Alternate reference and current validation within each sample.')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--compare-report', type=Path, help='Check matched output hashes and record timing deltas against a prior report.')
    args = parser.parse_args()
    if not 1 <= args.iterations <= 10000 or not 0 <= args.warmup <= 10000:
        parser.error('iterations must be 1..10000 and warmup 0..10000')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = (args.output_dir or ROOT/'benchmarks/local'/stamp).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output/'report.json').exists():
        raise RuntimeError(f'Existing report preserved: {output/"report.json"}')
    if args.builds and platform.system() != 'Darwin':
        raise RuntimeError('tvOS builds require macOS/Xcode')
    compiler = shutil.which('clang++') or shutil.which('g++')
    if not compiler:
        raise RuntimeError('A C++17 compiler is required')
    shader = (args.shader_source or ROOT/'native/apple/shaders/wavelet_dequant_apple5.metal').resolve()
    shader_copy = output/'wavelet_dequant_apple5.metal'
    if shader != shader_copy:
        shutil.copy2(shader, shader_copy)
    command = [compiler, '-std=c++17', '-O2', '-Wall', '-Wextra']
    if platform.system() == 'Darwin':
        from prepare_metal import prepare_metal
        metal = prepare_metal()
        command += ['-x', 'objective-c++', '-fobjc-arc', '-I'+str(metal)]
        command += [str(metal/name) for name in ['pyrowave_common.mm','pyrowave_decoder.mm']]
    command += ['-I'+str(ROOT/name) for name in [
        'tests', 'native/protocol', 'native/apple', 'native/client', 'third_party/pyrowave/metal']]
    framing = (args.framing_source or ROOT/'native/protocol/pyrowaveframing.cpp').resolve()
    command += [str(ROOT/'tools/benchmark_client.cpp'),str(framing),
        str(ROOT/'third_party/pyrowave/metal/pyrowave_bitstream.cpp')]
    if platform.system() == 'Darwin':
        command += ['-framework', 'Metal', '-framework', 'Foundation', '-framework', 'QuartzCore', '-framework', 'IOSurface']
    executable = output/'benchmark-client'
    command += ['-o', str(executable)]
    with (output/'build.log').open('w') as log:
        if args.compare_framing:
            command += ['-x','none']
            for source, name in [(args.compare_framing.resolve(),'reference'),
                                 (ROOT/'tools/benchmark_reference.cpp','reference-wrapper')]:
                object_path = output/(name+'.o')
                subprocess.run([compiler,'-std=c++17','-O2','-I'+str(ROOT/'native/protocol'),
                    '-DPyroWaveFraming=PyroWaveFramingBaseline','-c',str(source),
                    '-o',str(object_path)],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
                command.append(str(object_path))
            command.append('-DPW_BENCHMARK_REFERENCE')
        subprocess.run(command, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    command = [str(executable), '--iterations', str(args.iterations), '--warmup', str(args.warmup)]
    if args.cpu_only:
        command.append('--cpu-only')
    if platform.system() == 'Darwin':
        command += ['--shader-source', str(shader_copy)]
    with (output/'metrics.json').open('w') as metrics, (output/'run.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, check=True, stdout=metrics, stderr=log)
    report = json.loads((output/'metrics.json').read_text())
    report['revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
    report['worktree_dirty'] = bool(subprocess.check_output(['git','status','--porcelain'], cwd=ROOT, text=True).strip())
    report['architecture'] = platform.machine()
    report['system'] = platform.system()
    report['shader_sha256'] = hashlib.sha256(shader_copy.read_bytes()).hexdigest()
    report['framing_sha256'] = hashlib.sha256(framing.read_bytes()).hexdigest()
    if args.compare_framing:
        report['reference_framing_sha256'] = hashlib.sha256(args.compare_framing.read_bytes()).hexdigest()
    report['benchmark_sha256'] = hashlib.sha256((ROOT/'tools/benchmark_client.cpp').read_bytes()).hexdigest()
    if args.compare_report:
        reference = json.loads(args.compare_report.read_text())
        if reference['benchmark_sha256'] != report['benchmark_sha256']:
            raise RuntimeError('Benchmark sources differ from the reference report')
        if reference['gpu'].get('name') != report['gpu'].get('name'):
            raise RuntimeError('Reference report uses a different host GPU')
        old_cases = reference.get('full_decoder', {}).get('cases', [])
        new_cases = report.get('full_decoder', {}).get('cases', [])
        if not old_cases or len(old_cases) != len(new_cases):
            raise RuntimeError('Both reports must contain matching full-decoder cases')
        comparison = []
        for before, after in zip(old_cases, new_cases):
            identity = ['width','height','budget_mbps','zero_frame']
            if any(before[key] != after[key] for key in identity):
                raise RuntimeError('Full-decoder case definitions differ')
            if before['output_hash'] != after['output_hash']:
                raise RuntimeError('Full-decoder image checksum changed')
            case = {key:after[key] for key in identity}
            for metric in ['prepare_ms','decode_gpu_ms','color_gpu_ms','ready_gpu_end_ms']:
                old, new = before[metric], after[metric]
                case[metric] = None if old is None or new is None else {
                    'reference_p50':old['p50'], 'candidate_p50':new['p50'],
                    'reference_p95':old['p95'], 'candidate_p95':new['p95']}
            comparison.append(case)
        report['comparison'] = {'output_hashes_matched':len(comparison),'cases':comparison}
    report['builds'] = []
    if args.builds:
        for configuration, sdk in [('Debug','appletvsimulator'),('Release','appletvsimulator'),('Debug','appletvos'),('Release','appletvos')]:
            label = configuration+'-'+sdk
            with (output/(label+'.log')).open('w') as log:
                subprocess.run([sys.executable, str(ROOT/'tools/build_tvos.py'),
                    '--configuration', configuration, '--sdk', sdk], cwd=ROOT,
                    check=True, stdout=log, stderr=subprocess.STDOUT)
            report['builds'].append({'configuration':configuration,'sdk':sdk,'passed':True})
    (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(output/'report.json')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
