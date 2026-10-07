#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate or normalize a video and encode it with real encoders; never emulate PyroWave."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import platform
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PIN = '186f0393b77f7755953b5ecde994bb1cec2e4155'


def executable(name: str) -> str:
    result = shutil.which(name)
    if not result:
        raise RuntimeError(f'{name} not found; install it and add it to PATH.')
    return result


def run(command: list[str], log: Path, timeout: float) -> float:
    start = time.perf_counter()
    with log.open('w', encoding='utf-8') as output:
        try:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=timeout)
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f'{Path(command[0]).name} failed ({exc.returncode}); see {log}') from exc
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f'{Path(command[0]).name} exceeded {timeout}s; see {log}') from exc
    return time.perf_counter() - start


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inspect_container(path: Path, expected_frames: int, width: int, height: int, fps: int) -> dict:
    # The upstream offline PYROWAVE file is not a GameStream/RTP container.
    with path.open('rb') as source:
        header = source.read(40)
        if len(header) != 40 or header[:8] != b'PYROWAVE':
            raise RuntimeError('Encoder did not produce an upstream PyroWave offline file.')
        fields = struct.unpack('<8I', header[8:])
        if fields != (width, height, 0, 0, 0, fps, 1, 0):
            raise RuntimeError(f'Unexpected offline video profile: {fields}')
        count = total_bytes = largest = 0
        while True:
            word = source.read(4)
            if not word:
                break
            if len(word) != 4:
                raise RuntimeError('Truncated offline frame length.')
            length = struct.unpack('<I', word)[0]
            if length < 8 or length % 4 or length > 64 * 1024 * 1024:
                raise RuntimeError('Invalid offline frame size.')
            # Bounded read; no video-sized allocation.
            remaining = length
            while remaining:
                data = source.read(min(remaining, 1024 * 1024))
                if not data:
                    raise RuntimeError('Truncated encoded frame.')
                remaining -= len(data)
            count += 1
            total_bytes += length
            largest = max(largest, length)
        if count != expected_frames:
            raise RuntimeError(f'Encoded {count} frames, expected {expected_frames}.')
    return {'frames': count, 'payload_bytes': total_bytes, 'largest_frame_bytes': largest,
            'container_validated': True, 'payload_mbps': total_bytes * 8 * fps / count / 1_000_000}


def video_info(ffprobe: str, path: Path) -> dict:
    output = subprocess.check_output([ffprobe, '-v', 'error', '-count_frames', '-select_streams', 'v:0',
                                      '-show_entries', 'stream=width,height,pix_fmt,nb_read_frames,r_frame_rate',
                                      '-of', 'json', str(path)], text=True, timeout=120)
    streams = json.loads(output).get('streams', [])
    if len(streams) != 1:
        raise RuntimeError('Expected one video stream.')
    return streams[0]


def args_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, help='Optional own video; otherwise generate motion, gradients and text.')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'benchmarks/local/video-test')
    parser.add_argument('--width', type=int, default=1280)
    parser.add_argument('--height', type=int, default=720)
    parser.add_argument('--fps', type=int, default=60)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--codecs', default='pyrowave,h264,hevc')
    parser.add_argument('--backend', choices=['metal', 'vulkan'], default='metal' if platform.system() == 'Darwin' else 'vulkan')
    parser.add_argument('--encoder', type=Path, help='Metal pyrowave-video or pinned upstream Vulkan pyrowave-encode executable.')
    parser.add_argument('--framing-check', type=Path, default=ROOT / 'build/portable/framing-check')
    parser.add_argument('--encoder-commit', help='Actual external Vulkan encoder source revision; not guessed from its filename.')
    parser.add_argument('--bitrate-mbps', type=float, default=400)
    parser.add_argument('--roundtrip', action='store_true', help='Decode PyroWave with the Metal tool and compare reconstruction using PSNR.')
    parser.add_argument('--timeout', type=float, default=600)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = args_parser().parse_args(argv)
    report = {'schema_version': 1, 'status': 'running', 'purpose': 'offline-encoder-functional-test',
              'apple_tv_benchmark': False, 'auto_qualified': False, 'encoders': {}}
    report_path = None
    try:
        codecs = args.codecs.split(',')
        if not codecs or len(set(codecs)) != len(codecs) or any(c not in {'pyrowave', 'h264', 'hevc'} for c in codecs):
            raise RuntimeError('Choose distinct codecs from pyrowave,h264,hevc.')
        if not (128 <= args.width <= 16384 and 128 <= args.height <= 16384 and args.width % 2 == args.height % 2 == 0):
            raise RuntimeError('Use even width/height in 128..16384 for this 8-bit 4:2:0 harness.')
        if args.frames < 1 or args.frames > 100000 or args.fps < 1 or args.fps > 240:
            raise RuntimeError('Use frames 1..100000 and FPS 1..240.')
        if not math.isfinite(args.timeout) or args.timeout <= 0 or not math.isfinite(args.bitrate_mbps) or args.bitrate_mbps <= 0:
            raise RuntimeError('Timeout and bitrate must be positive finite numbers.')
        if args.roundtrip and ('pyrowave' not in codecs or args.backend != 'metal'):
            raise RuntimeError('--roundtrip requires the Metal PyroWave encoder/decoder.')
        ffmpeg, ffprobe = executable('ffmpeg'), executable('ffprobe')
        out = args.output_dir.resolve()
        # A fresh run cannot overwrite old evidence or pretend old output was produced now.
        out.mkdir(parents=True, exist_ok=False)
        report_path = out / 'report.json'
        if args.input is not None and not args.input.is_file():
            raise RuntimeError('Input video does not exist.')
        encoder = args.encoder.resolve() if args.encoder else ROOT / 'build/metal/pyrowave-video'
        if 'pyrowave' in codecs:
            if args.backend == 'vulkan' and not args.encoder:
                raise RuntimeError('Vulkan encoding requires --encoder /path/to/pyrowave-encode; FFmpeg does not encode PyroWave.')
            if not encoder.is_file():
                raise RuntimeError('PyroWave encoder missing. On macOS run python tools/build_engine.py; for Vulkan provide --encoder.')
            if not args.framing_check.is_file():
                raise RuntimeError('Run python tools/run_portable_tests.py first to build framing-check.')
            if args.backend == 'vulkan' and args.encoder_commit != PIN:
                raise RuntimeError(f'Provide --encoder-commit {PIN} only for an encoder actually built from that pinned source.')
            if args.backend == 'metal':
                version = subprocess.check_output([str(encoder), '--version'], text=True, timeout=10)
                if 'bitstream=186f0393' not in version:
                    raise RuntimeError('Unexpected Metal tool version.')
        if args.width * args.height * args.frames * 3 // 2 > 8 * 1024**3:
            raise RuntimeError('Raw fixture exceeds the 8 GiB safety limit; reduce frames or size explicitly.')
        required = args.width * args.height * args.frames * 3 // 2
        if shutil.disk_usage(out).free < required * (3 if args.roundtrip else 2):
            raise RuntimeError('Insufficient free disk space for fixture and reconstruction.')
        source = out / 'source.y4m'
        command = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-threads', '1', '-filter_complex_threads', '1']
        if args.input:
            command += ['-i', str(args.input.resolve()), '-vf', f'scale={args.width}:{args.height},fps={args.fps},format=yuv420p']
            source_description = 'user-supplied-video-normalized-to-explicit-profile'
        else:
            command += ['-f', 'lavfi', '-i', f'testsrc2=size={args.width}x{args.height}:rate={args.fps}',
                        '-f', 'lavfi', '-i', f'gradients=s={args.width}x{args.height}:r={args.fps}:c0=black:c1=white:x0=0:y0=0:x1={args.width}:y1={args.height}:seed=42:speed=0.03',
                        '-filter_complex', f"[0:v][1:v]blend=all_expr='A*0.8+B*0.2',drawtext=text='PyroWave motion and gradients':fontsize={max(12,args.height//24)}:fontcolor=white:box=1:boxcolor=black@0.65:x=12:y=12,format=yuv420p[v]", '-map', '[v]']
            source_description = 'generated-ffmpeg-motion-gradient-text-seed42'
        command += ['-frames:v', str(args.frames), '-an', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-f', 'yuv4mpegpipe', str(source)]
        run(command, out / 'generate.log', args.timeout)
        info = video_info(ffprobe, source)
        if int(info.get('nb_read_frames', 0)) != args.frames or info.get('pix_fmt') != 'yuv420p':
            raise RuntimeError('Source does not contain the requested number/profile of frames; no looping or silent padding.')
        report['source'] = {'description': source_description, 'sha256': hash_file(source), 'profile': info}
        for codec in codecs:
            entry = {'status': 'running', 'gpu_encode_ms': None, 'gpu_decode_ms': None,
                     'auto_qualified': False, 'wall_time_is_per_frame_latency': False}
            report['encoders'][codec] = entry
            if codec == 'pyrowave':
                target = out / 'encoded.pyrowave'
                budget = math.floor(args.bitrate_mbps * 1_000_000 / 8 / args.fps)
                if budget < 64 or budget > 16 * 1024 * 1024:
                    raise RuntimeError('Requested PyroWave per-frame budget is outside this harness limit.')
                command = [str(encoder)] + (['encode'] if args.backend == 'metal' else []) + [str(source), str(target), str(budget)]
                entry.update(backend=args.backend, encoder_binary_sha256=hash_file(encoder), encoder_commit=PIN, maximum_bytes_per_frame=budget)
                entry['encode_process_wall_seconds'] = run(command, out / 'pyrowave-encode.log', args.timeout)
                entry.update(inspect_container(target, args.frames, args.width, args.height, args.fps))
                validation = subprocess.check_output([str(args.framing_check.resolve()), str(target)], text=True, timeout=args.timeout)
                checked = json.loads(validation)
                if checked['frames'] != args.frames:
                    raise RuntimeError('Nonary framing validator frame count mismatch.')
                entry['nonary_framing_validated'] = checked['nonary_framing_validated']
                if args.roundtrip:
                    reconstruction, metrics = out / 'reconstructed.y4m', out / 'metal-decode.json'
                    entry['decode_process_wall_seconds'] = run([str(encoder), 'decode', str(target), str(reconstruction), str(metrics)], out / 'pyrowave-decode.log', args.timeout)
                    decoded_info = video_info(ffprobe, reconstruction)
                    if int(decoded_info.get('nb_read_frames', 0)) != args.frames:
                        raise RuntimeError('Reconstruction frame count mismatch.')
                    entry['offline_decode_metrics'] = json.loads(metrics.read_text())
                    run([ffmpeg, '-hide_banner', '-nostdin', '-i', str(source), '-i', str(reconstruction), '-lavfi', 'psnr', '-f', 'null', '-'], out / 'psnr.log', args.timeout)
                    entry['reconstruction_compared'] = True
            else:
                target = out / f'{codec}.mkv'
                options = ['-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-crf', '18'] if codec == 'h264' else ['-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'pools=1:frame-threads=1:bframes=0:log-level=error', '-crf', '18']
                entry.update(backend='ffmpeg-cpu-reference', crf=18, preset='ultrafast')
                entry['encode_process_wall_seconds'] = run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-threads', '1', '-i', str(source), *options, '-an', str(target)], out / f'{codec}-encode.log', args.timeout)
                encoded_info = video_info(ffprobe, target)
                if int(encoded_info.get('nb_read_frames', 0)) != args.frames:
                    raise RuntimeError(f'{codec} output frame count mismatch.')
                run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-threads', '1', '-i', str(target), '-f', 'framemd5', str(out / f'{codec}-decoded.framemd5')], out / f'{codec}-decode.log', args.timeout)
                entry['decode_functional_check'] = True
            entry.update(status='passed', output_bytes=target.stat().st_size, output_sha256=hash_file(target))
            report_path.write_text(json.dumps(report, indent=2) + '\n')
        report['status'] = 'passed'
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Encoding checks passed: {report_path}')
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as exc:
        report.update(status='failed', error=str(exc))
        for entry in report['encoders'].values():
            if entry['status'] == 'running': entry['status'] = 'failed'
        if report_path:
            report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Encoding test failed: {exc}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
