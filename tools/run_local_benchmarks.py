#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run isolated CPU/Metal stage benchmarks and optional unsigned tvOS builds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def latency_gate(report, limit):
    """Fail closed on incomplete coverage or timing; wall time includes GPU waits."""
    cases = report.get('full_decoder', {}).get('cases', [])
    expected = {(w,h,b) for w,h in [(1280,720),(1920,1080),(3840,2160)]
                for b in [150,300,500,1000]}
    actual = {(c['width'],c['height'],c['budget_mbps']) for c in cases if not c['zero_frame']}
    reasons = []
    if not report.get('full_decoder_tested') or actual != expected:
        reasons.append('Full decoder profile coverage is incomplete')
    if report.get('iterations',0) < 100:
        reasons.append('At least 100 measured samples per profile are required')
    for case in cases:
        for metric in ['decode_gpu_ms','ready_wall_ms']:
            timing = case.get(metric)
            if (not timing or timing.get('samples') != report.get('iterations') or
                not math.isfinite(timing.get('p95',float('nan'))) or
                not 0 < timing['p95'] < limit):
                reasons.append(f"{case['width']}x{case['height']} {case['budget_mbps']} Mbps {metric} failed")
    return {'passed':not reasons,'threshold_ms':limit,'percentile':'p95',
            'metrics':['decode_gpu_ms','ready_wall_ms'],'reasons':reasons,
            'scope':'synthetic offscreen; no drawable, transport or physical A12 qualification'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=int, default=100)
    parser.add_argument('--warmup', type=int, default=20)
    parser.add_argument('--cpu-only', action='store_true')
    parser.add_argument('--simulator', metavar='UDID', help='Compile for tvOS and execute in a booted simulator; host GPU performance only.')
    parser.add_argument('--max-decode-p95-ms', type=float, help='Require full profile coverage and p95 decode GPU and total wall time below this limit (100+ samples).')
    parser.add_argument('--builds', action='store_true', help='Build Debug and Release for simulator and device in the existing project.')
    parser.add_argument('--shader-source', type=Path)
    parser.add_argument('--framing-source', type=Path)
    parser.add_argument('--compare-framing', type=Path, help='Alternate reference and current validation within each sample.')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--compare-report', type=Path, help='Check matched output hashes and record timing deltas against a prior report.')
    args = parser.parse_args()
    if not 1 <= args.iterations <= 10000 or not 0 <= args.warmup <= 10000:
        parser.error('iterations must be 1..10000 and warmup 0..10000')
    if args.max_decode_p95_ms is not None and (not math.isfinite(args.max_decode_p95_ms) or args.max_decode_p95_ms <= 0):
        parser.error('Latency limit must be finite and positive')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = (args.output_dir or ROOT/'benchmarks/local'/stamp).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output/'report.json').exists():
        raise RuntimeError(f'Existing report preserved: {output/"report.json"}')
    if (args.builds or args.simulator) and platform.system() != 'Darwin':
        raise RuntimeError('tvOS builds require macOS/Xcode')
    compiler = shutil.which('clang++') or shutil.which('g++')
    if not compiler:
        raise RuntimeError('A C++17 compiler is required')
    shader = (args.shader_source or ROOT/'native/apple/shaders/wavelet_dequant_apple5.metal').resolve()
    shader_copy = output/'wavelet_dequant_apple5.metal'
    if shader != shader_copy:
        shutil.copy2(shader, shader_copy)
    command = [compiler, '-std=c++17', '-O2', '-Wall', '-Wextra']
    target_flags = []
    if platform.system() == 'Darwin':
        from prepare_metal import prepare_metal
        metal = prepare_metal()
        command += ['-x', 'objective-c++', '-fobjc-arc', '-I'+str(metal)]
        if args.simulator:
            sdk = subprocess.check_output(['xcrun','--sdk','appletvsimulator','--show-sdk-path'], text=True).strip()
            target_flags = ['-target',platform.machine()+'-apple-tvos18.0-simulator','-isysroot',sdk]
            command += target_flags
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
                subprocess.run([compiler,*target_flags,'-std=c++17','-O2','-I'+str(ROOT/'native/protocol'),
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
    if args.simulator:
        subprocess.run(['codesign','--sign','-','--force',str(executable)], check=True, stdout=subprocess.DEVNULL)
        command = ['xcrun','simctl','spawn',args.simulator,*command]
    with (output/'metrics.json').open('w') as metrics, (output/'run.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, check=True, stdout=metrics, stderr=log)
    report = json.loads((output/'metrics.json').read_text())
    report['revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
    report['worktree_dirty'] = bool(subprocess.check_output(['git','status','--porcelain'], cwd=ROOT, text=True).strip())
    report['architecture'] = platform.machine()
    report['system'] = 'tvOS Simulator' if args.simulator else platform.system()
    if args.simulator:
        inventory = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j'], text=True))
        matches = [(runtime,device) for runtime,devices in inventory['devices'].items()
                   for device in devices if device['udid'] == args.simulator]
        if len(matches) != 1:
            raise RuntimeError('Simulator UDID not found in device inventory')
        runtime, device = matches[0]
        report['simulator'] = {'runtime':runtime,'device_type':device['deviceTypeIdentifier'],
                               'name':device['name'],'hardware_emulation':False}
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
    if args.max_decode_p95_ms is not None:
        report['latency_gate'] = latency_gate(report,args.max_decode_p95_ms)
    (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(output/'report.json')
    if report.get('latency_gate',{}).get('passed') is False:
        raise RuntimeError('Latency gate failed; see report.json')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
