# Client timing and latency

The renderer records rolling p50/p95/p99 distributions with up to 2,048 samples
per timing series. The overlay shows p95. A p95 is the threshold containing 95%
of recorded samples, not the time of every frame.

## Implemented measurements

| Statistic | Boundaries |
| --- | --- |
| `submit_to_worker_ms` | Renderer entry to mailbox pickup, including payload ownership/copy and scheduling |
| `input_queue_ms` | Common-c enqueue to delivery at renderer entry, using the common-c microsecond clock |
| `copy_cpu_ms` | Renderer entry to payload ownership/copy completion, including initial lock acquisition |
| `prepare_cpu_ms` | Worker pickup to decode commit preparation, including framing, packet preparation and command encoding/upload |
| `drawable_wait_ms` | Time in `CAMetalLayer nextDrawable`, after decode submission |
| `decode_queue_ms` | Timestamp immediately before decode commit to that command buffer's GPU start |
| `render_queue_ms` | Timestamp immediately before conversion commit to that command buffer's GPU start |
| `gpu_decode_ms` | Decode command-buffer GPU start to GPU end |
| `color_gpu_ms` | Conversion command-buffer GPU start to GPU end |
| `decode_and_color_gpu_ms` | Sum of the two command-buffer execution durations for a completed frame |
| `gpu_callback_delay_ms` | Conversion GPU end to its completion callback |
| `client_ready_gpu_end_ms` | Renderer entry to conversion GPU end |
| `submit_to_presented_ms` | Renderer entry to the drawable's OS-reported presentation time on device builds |

Each distribution retains up to 2,048 valid samples. Decode GPU/queue samples
cover successful decode completions, including frames whose presentation was
subsequently abandoned. Worker, copy, prepare, input queue, drawable and conversion
samples cover frames whose decode and conversion both completed successfully.
Presentation samples come from drawable callbacks with valid positive timestamps.
`presentation_timing_available` is false in the tvOS Simulator, whose SDK omits
these drawable callback APIs. An empty timing series is reported as null.

`decoded_frames`, `completed_frames` and `presented_frames` count successful
decode commands, successful decode/conversion pairs and valid OS presentation
observations respectively. `present_failed` counts conversion encoding/execution
failures separately from `decode_failed` and unavailable-drawable drops.

`last_completed_frame` preserves frame number, RTP timestamp, common-c receive,
enqueue and delivery timestamps, plus renderer-entry, decode-commit, conversion-
commit and GPU boundaries. Common-c values are microseconds in its own clock.
Renderer/Metal values use host-time seconds. Compare intervals within each clock
domain. Snapshots include `snapshot_time_seconds` for calculating counter deltas.

Ready covers local ownership/copy, CPU work, waits and GPU execution through
conversion completion. Input reassembly and common-c queue residence have their
own boundaries. The OS presentation timestamp records compositor feedback.
Controller-to-screen and physical-panel latency require external measurement.

Percentiles are calculated independently. With the split submission path,
decoding can overlap drawable waiting. The combined GPU field now sums two
command-buffer durations and excludes their intervening gap. Historical combined
GPU samples came from one command buffer. Align measurement boundaries before
comparing those values. At 60 FPS the source interval is 16.67 ms.

## Recorded observations

The [device observations](development-status.md#apple-tv-device-observations)
include A12 live streaming and screenshots with Ready p95 near 71–74 ms. The
71.33 ms screenshot includes a combined GPU p95 of 22.32 ms and drawable-wait p95
of 25.89 ms. It is not a decoder-only benchmark or a matched HEVC comparison.
No controlled decoding or physical-presentation latency result is recorded for A15.

## Current scheduling

The serial worker commits GPU decode before acquiring a drawable, then submits
color conversion and presentation on the same Metal command queue. Private plane
textures use Metal's tracked resource dependencies. The layer has three drawable
resources. The mailbox retains two occupied processing slots plus one newest
pending frame. `processing_slots` and the compatibility field `gpu_in_flight`
count occupied processing slots, including CPU/drawable waits.

Each slot remains occupied until the decode completion callback and the conversion
completion or abandonment have both resolved. A missing drawable, stop, or
conversion-encoding failure preserves the slot while its submitted decode is
outstanding. Both callbacks retain the runtime. Payload copying takes place
outside the completion lock, with stop checked again before mailbox admission.

The Apple5 dequantizer and inverse wavelet shaders retain their previous dispatch
structure. Per-shader timing remains an additional profiling step.
The [source comparison with Nonary Moonlight and Pyrolight](scheduling-comparison.md)
records the pre-change pipeline and the reference architectures. Physical A12
measurements will establish the new scheduling path's performance.

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
