# Client timing and latency

The renderer records rolling p50/p95/p99 distributions with up to 2,048 samples
per timing series. The overlay shows p95. A p95 is the threshold containing 95%
of recorded samples, not the time of every frame.

## Implemented measurements

| Statistic | Boundaries |
| --- | --- |
| `submit_to_worker_ms` | Entry to `submitDecodeUnit` through mailbox pickup on the worker; includes validation/copy and client scheduling before pickup |
| `drawable_wait_ms` | Time spent in `CAMetalLayer nextDrawable` on the worker |
| `decode_and_color_gpu_ms` | Metal command-buffer GPU start to GPU end; includes decode and color conversion |
| `gpu_callback_delay_ms` | GPU end to entry into the completion callback |
| `client_ready_gpu_end_ms` | Renderer submission to GPU end |
| `gpu_decode_ms` | Null: decoder-only GPU timing is not separately measured |

The current Ready measurement ends at Metal's GPU end timestamp, unlike the
older completion-callback proxy. GPU samples are retained only when timestamps
are available and ordered consistently with submission and callback time. Worker
and drawable samples are retained for successful completions. Sorting snapshots
happens outside the submission lock.

Ready covers CPU preparation, waits and GPU work after renderer submission.
It does not measure host capture, packet reassembly before renderer submission,
physical presentation or controller-to-screen latency. The four stage percentiles
cannot be added to reconstruct Ready p95: each percentile may describe different
frames, and CPU parsing/encoding and GPU queue wait are not separate overlay fields.

At 60 FPS the arrival interval is 16.67 ms. That is not an independent allowance
for every stage. Throughput, latency and dropped work must be read together.
Only completed frames contribute these timing samples; skipped/replaced frames
remain visible in separate counters.

## Recorded observations

The [device observations](development-status.md#apple-tv-device-observations)
include A12 live streaming and screenshots with Ready p95 near 71–74 ms. The
71.33 ms screenshot includes a combined GPU p95 of 22.32 ms and drawable-wait p95
of 25.89 ms. It is not a decoder-only benchmark or a matched HEVC comparison.
No controlled decoding or physical-presentation latency result is recorded for A15.

## Findings from source inspection

The renderer calls `nextDrawable` before encoding and committing decode plus
color conversion. Consequently a blocked drawable request delays submission of
that frame's GPU work and occupies the serial worker. It uses a two-drawable pool.
The snapshot field `GPU/pending` counts occupied processing slots, including CPU
preparation/drawable waits, rather than only executing GPU commands.

The Apple5 dequantizer uses two 128-thread prefix scans and seven threadgroup
barriers per active tile. The inverse wavelet stages retain upstream dispatches
and inter-level dependencies. FP16 wavelet storage with FP32 lifting math is
already the default. These are source observations; there is no per-shader timing
that attributes the measured GPU time to one operation.

The live pipeline still uses one command buffer for decode and color conversion.
Separating decode from drawable acquisition, changing prefix scans and adding
per-shader timing have not been implemented. No measured speedup is claimed.

## Reading a comparison

Record the build, device/OS, backend, scene, resolution/FPS, requested and applied
bitrate, network route, measurement interval and counter deltas. Keep host,
network RTT, client GPU execution and visible presentation measurements separate.
A standard decoder's enqueue time is not equivalent to PyroWave GPU execution.
The selected bitrate is not measured network throughput.

Raw local captures belong in ignored `benchmarks/local/`. The
[report template](../benchmarks/templates/report.json) uses null for unavailable
measurements. It contains no populated Apple TV qualification result.

## API references

- [Metal GPU execution timestamps](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime)
- [CAMetalLayer drawable lifecycle](https://developer.apple.com/documentation/quartzcore/cametallayer)
- [Renderer implementation](../native/apple/PyroWaveVideoRenderer.mm)
