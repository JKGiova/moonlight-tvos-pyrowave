# Client decode performance specification

Status: experimental targets and planned measurement protocol. No device result is populated.

## Optimize latency and throughput separately

A high FPS benchmark does not imply low input-to-display latency. At 60 Hz, the frame interval is 16.67 ms; use per-frame critical-path latency, sustained processing throughput and bounded queue depth together.

| Metric | Definition |
| --- | --- |
| parse_cpu | Payload availability to validated packets |
| upload_cpu | CPU preparation/copy into retained GPU upload storage |
| gpu_decode | GPU execution of dequantization plus iDWT |
| gpu_color_conversion | Y/Cb/Cr to drawable color conversion |
| gpu_queue_wait | Submission to execution start; record separately when observable |
| client_ready | Fully reassembled payload to decoded, color-converted frame ready to present |
| present_wait | Ready frame to observed/presented output, separate from decoding |
| startup | Shader/pipeline creation, preflight and first-frame cost |
| sustained_throughput | Decode-only and live FPS with queue/drop statistics |

GPU timestamps/counter samples require capability checks. Mark unavailable measurements null and include the measurement method. Do not combine CPU monotonic and GPU timestamps without calibration. Use callback timings as explicitly labelled proxies when counters are unavailable. Native counters added in newer upstream revisions are optional and do not change the pinned bitstream without review.

## Initial qualification gates

The frame budget B is 1000/FPS milliseconds. These are provisional admission limits, not measurements:

| Gate | Proposed limit |
| --- | --- |
| GPU decode p95 | <= 0.50 B |
| GPU decode p99 | <= 0.75 B |
| Full client-ready p95 | <= 0.75 B |
| Full client-ready p99 | <= 1.00 B |
| Decode-only throughput | >= 1.20 x requested FPS |
| Memory/queue stability | No persistent growth; maximum 2 GPU frames plus 1 pending |
| Cross-codec Auto comparison, when comparable | PyroWave ready p95 <= fastest qualifying hardware fallback + 0.5 ms |
| Network | Useful throughput headroom >= 20%, plus live UDP validation |

At 60 FPS these imply GPU decode p95 <= 8.33 ms and client-ready p95 <= 12.5 ms. A decoder that merely averages under 16.67 ms is not qualified for low-latency Auto.

Aspirational GPU decode p95 goals are <= 2 ms at 1080p60 and <= 4 ms at 4K60. They are optimization goals only and must not be advertised as expected performance on any target device.

## Optimization order

1. Validate the implemented experimental Apple5 dequantization with portable threadgroup scans on A12; preserve and qualify the native Apple7-or-later fast path on A15. Verify equivalent output where both paths can run; choose using real capabilities and pipeline limits.
2. Stable memory lifetime and pool reuse; no per-frame texture/pipeline allocation.
3. FP32 reference versus FP32 arithmetic with FP16 storage.
4. Keep decoded planes on the GPU; avoid CPU readback and unnecessary conversions.
5. Precompile/warm shader pipelines; report startup separately.
6. Profile dequant, individual iDWT levels, upload, color conversion and present scheduling.
7. Compare compute with a Metal rendering-pass iDWT experiment only if profiling justifies it.
8. Tune groups, barriers and pass fusion only with equivalent output and physical-device wins.

Two in-flight frames are an upper bound, not a target backlog. Prefer the smallest pool that sustains the requested frame rate. Drop/replace pending stale work rather than accumulating a queue. A large socket receive buffer absorbs bursts; it is not permission to decode an old backlog.

## Benchmark matrix and procedure

- Physical A12 and A15 bring-up; release validation on A2169, A2737 and A2843 from the [device matrix](device-support.md). Keep model/backend/OS/profile result sets separate.
- Qualify both third-generation variants independently, including thermal soak and network behavior. A shared SoC is not permission to copy an Auto qualification record.
- 720p60 bring-up, 1080p60 qualification, 4K60 qualification.
- SDR 8-bit 4:2:0 first; every additional color profile gets separate admission.
- Workloads: flat fields, gradients, text, random/detail stress and representative game captures.
- Use the same captures/profile for comparisons; fix quality and record bitrates instead of silently degrading one codec.
- Warm up, collect at least 10,000 steady-state frames, and run a separate >=30 minute soak.
- Alternate/randomize codec order and repeat trials to reduce thermal/order bias.
- Run offline decode and live streaming; live tests include Wi-Fi on every model and Ethernet on A2169/A2843, plus UDP burst loss/jitter. A2737 has no Ethernet route.
- Record accepted/rejected frame counts and drops; do not hide slow frames by reporting only completed fast frames.
- Compare hardware paths with equivalent observable boundaries; AVSampleBufferDisplayLayer enqueue duration is not GPU decode time.

Store raw timestamps locally under benchmarks/local/ (ignored). Commit only sanitized summaries after real measurements, using benchmarks/templates/report.json. Null means not measured; it never passes an Auto gate.

Host capture/encoding latency is recorded separately. Reducing client decode time cannot, by itself, establish that a host-processing stall has been resolved.

## Monitor overhead

The [five-second host monitor](host-network-monitor.md) runs only on the selected PC dashboard. All requests, DNS/ICMP work and timers are canceled before streaming; launch/resume waits for cancellation completion. Physical validation must check that no probe remains active during decoder measurements. The bounded HTTPS bandwidth test is pre-stream only; it includes connection setup and does not prove UDP capacity. Passive in-stream goodput is future work.
