# Development status

Documentation snapshot: 2026-11-24. This page includes the split decode/conversion scheduling update following
`0d68cb8`, with decode committed before drawable acquisition. It distinguishes
source implementation, automated checks and owner-reported device observations.

## Implemented client

| Area | Current implementation |
| --- | --- |
| App | Pinned Moonlight project, standard PC/app UI and PIN pairing; installed name Moonlight Pyro |
| Live PyroWave | Complete-frame 8-bit SDR / 10-bit HDR10 in 420/444, exact identity validation, Metal/CV presentation; new profiles await live qualification |
| Backend | Portable Apple5 for A12; native Apple7-or-later candidate selected through capability/pipeline checks |
| Frame delivery | Dedicated PyroWave receive worker waits for common-c frames; standard codecs retain display-link polling |
| Scheduling | Two occupied decoder/texture slots, one latest pending frame and three drawables; decode commits before drawable acquisition; both stages resolve before slot release |
| Settings | Persistent PyroWave 4:2:0/4:4:4 and HDR profile toggle, manual requests through 1,000 Mbps and per-profile bitrate Auto capped at 500 Mbps for PyroWave |
| Timing | GPU-end Ready, isolated decode/conversion and queue timing, retained frame timestamps, device presentation callbacks and separate error/drop counters |
| Source preparation | One reusable generated client, exact-pin checks, selective patches, recorded file baselines and project merging that preserves signing edits |
| Reference monitor | Dashboard/transport/policy sources retained; dashboard patch excluded from the standard generated client |

The split-command-buffer path compiles for the simulator and is covered by
portable completion-order/abandonment tests and the GPU presenter's split-submission
fixture. The recorded A12 screenshots below predate this update. Collect physical
device measurements before attributing a latency improvement to it.

## Practical checks and next steps

[Plain-language tests](practical-tests.md) explain the new Mac checks of all 1,024
10-bit levels, one-pixel 4:4:4 chroma, bounded queues, pool recovery and strict
profile selection. They distinguish these checks from the earlier physical A12
timings. The new device attempt was refused while the Apple TV was asleep; no new
device measurement is claimed. [Roadmap and completion criteria](ROADMAP.md)

## Color profile implementation

HDR10 and full-resolution chroma are implemented in the single client. A physical
A12 offscreen diagnostic passed eight complete decoder cases (two dimensions ×
two chroma layouts × R8/R16 output) and eight PQ/SDR packing cases with 294,912
exact component comparisons. Exit status was zero and thermal state nominal.
[Sanitized evidence](../benchmarks/results/2026-11-24-a12-color-profiles.json)

These checks do not test HDR HDMI output, live stream quality or sustained 4K60.
HDR10+ is not implemented: the inspected host protocol lacks dynamic-metadata
transport, and the A12 model does not list HDR10+ output support.
[Profiles, setup and remaining work](video-profiles.md)

## Apple TV device observations

These observations were supplied by the owner. Different builds, scenes and
measurement intervals prevent treating them as a controlled comparison. Client
bitrate settings are not measurements of on-wire throughput.

| Observation | Playback/counters | Ready p95 |
| --- | --- | ---: |
| Earlier A12 run, manual 150 Mbps | Reported 30 minutes of 4K60 PyroWave, zero queue drops | About 60 ms; exact timing revision unspecified |
| Separate screenshot, reported 300 Mbps setting | 3840×2160, 59.94 stream FPS, 1,299 queue drops, GPU/pending 1/1; parser/decode/present counters zero | 74.02 ms |
| Screenshot with four-stage timing, bitrate/duration unspecified | 3840×2160, 39.79 stream FPS, 1,221 queue drops, GPU/pending 1/0; parser/decode/present counters zero | 71.33 ms (GPU end) |

The 74.02 ms screenshot shows 0.00% network frame loss, 6 ms RTT and 3 ms variance.
The 71.33 ms screenshot shows 0.00% network frame loss, 1 ms RTT with zero variance,
and host processing min/max/average of 0.9/1.6/1.0 ms. Its stage p95 values are:

| Submit to worker | Drawable wait | GPU decode + conversion | Callback delay |
| ---: | ---: | ---: | ---: |
| 15.98 ms | 25.89 ms | 22.32 ms | 0.28 ms |

Queue drops are cumulative client pending-frame replacements. Zero network loss
in the displayed sample window does not imply zero client drops. No drop rate can
be derived without an interval. Percentiles must not be summed.

The owner also reported roughly 120 Mbps of traffic at 4K and up to 300 Mbps at
1440p with a high configured budget. Comparable host logs/FPS and applied bitrate
are not recorded; no fixed 120 Mbps cap or causal explanation is established.
No matched HEVC latency result or physical A15 result is recorded.

## Local testbench update

The [2026-11-23 host record](../benchmarks/results/2026-11-23-local-testbenches.json)
covers paired CPU validation, 24 tiled dequant workloads, 14 complete offscreen
decoder/conversion cases and four local tvOS builds. The CPU validator uses byte
population counts, and the portable shader uses four barriers per active group.
Paired synthetic 4K validation medians fell by approximately 42–51% on this host.
All 14 full-decoder output checksums matched the reference, and tiled dequant
coefficient errors were zero. Host GPU timing changes were small. This evidence
belongs to the host lab workloads. Physical A12 live-stream latency for these changes remains
to be measured; the offline device diagnostic below has its own scope. [Running the testbenches](local-testbenches.md)

## Physical A12 offline diagnostic

The [2026-11-24 device record](../benchmarks/results/2026-11-24-a12-offline-device.json)
uses an Apple TV 4K second generation (`AppleTV11,1`), Apple A12 GPU, tvOS 27.0
build 24J361. With the host PC offline, four temporary signed diagnostic launches
ran candidate/baseline/candidate/baseline through the normal production Apple5
factory. Each tested 14 complete synthetic profiles, 100 timed frames and 20 warmup
per profile, plus 24 isolated coefficient workloads. All 56 output checksums
matched; 364,380,160 coefficient comparisons had maximum error zero. Thermal
state was nominal at the start and end of all four runs.

Candidate 4K p95 ranges across its two runs:

| Payload budget, 60 FPS equivalent | Decode GPU | Preparation + decode + conversion wall time |
| --- | --- | --- |
| 150 Mbps | 15.37–20.95 ms | 20.40–27.04 ms |
| 300 Mbps | 19.93–22.85 ms | 27.28–32.49 ms |
| 500 Mbps | 22.55–25.33 ms | 31.09–36.20 ms |
| 1,000 Mbps | 25.45–26.55 ms | 36.81–44.56 ms |

These ranges describe two observed p95 values, not confidence intervals. Device
GPU clocks/system rendering were not fixed. The first worker needed a debugger
trigger after an inactive launch; the debugger was then detached. Subsequent
workers started automatically at launch. The
before/after results do not establish a reliable physical speedup. At 500 Mbps,
both candidate runs have higher decode and wall p95 than both baseline runs.
The simulator's percentage gains must not be presented as Apple TV gains.
No live transport, drawable, compositor, controller/panel latency or sustained
4K60 presentation was tested. Auto qualification remains unchanged. The temporary
harness is removed from the normal signed app after testing; normal sources are
restored even on build failure. [Reproduction](local-testbenches.md#offline-a12-device-diagnostic)

## Automated evidence

| Check record | Recorded result and boundary |
| --- | --- |
| [Initial integration](../benchmarks/results/2026-10-07-live-integration-ci.json) | Integrated unsigned tvOS build, Metal presenter and portable checks; native codec GPU round trip skipped by the runner's support gate |
| [Apple5 checks](../benchmarks/results/2026-10-08-apple5-ci-checks.json) | 32,768 GPU reference coefficients matched exactly; six iDWT variants compiled; two uniform synthetic frames decoded; unsigned tvOS and Metal harness builds passed |
| [Reliability checks](../benchmarks/results/2026-10-09-reliability-ci-checks.json) | 100,075 runtime checks, 16 Python tests, four CTest cases, mutation/parser corpus and presenter pixels; 20 upstream analyzer findings recorded |
| [Post-merge CI at f57c5ab](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/44893326699) | Five jobs passed, including device Debug/Release, simulator, portable and Metal checks; this evidence belongs to that revision |

Older CI success is not a claim that every later commit passed. Current run
results are available in [GitHub Actions](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions).
Hosted Mac GPU fixtures and unsigned builds do not establish Apple TV latency or
physical-display behavior. [Reliability diagnostics](reliability-and-xcode.md)
