# Development status

Documentation snapshot: 2026-11-23. This page describes the implementation through
`7a9a0cb`, including the `afbda5f` scheduling/timing changes. It distinguishes
source implementation, automated checks and owner-reported device observations.

## Implemented client

| Area | Current implementation |
| --- | --- |
| App | Pinned Moonlight project, standard PC/app UI and PIN pairing; installed name Moonlight Pyro |
| Live PyroWave | Complete-frame 8-bit SDR 4:2:0, exact bitstream identity validation and Metal presentation |
| Backend | Portable Apple5 for A12; native Apple7-or-later candidate selected through capability/pipeline checks |
| Frame delivery | Dedicated PyroWave receive worker waits for common-c frames; standard codecs retain display-link polling |
| Scheduling | Two occupied decoder/texture slots and one latest pending frame; completion releases slots |
| Settings | Persistent PyroWave (SDR), manual requests through 1,000 Mbps and per-profile bitrate Auto capped at 500 Mbps for PyroWave |
| Timing | GPU-end Ready, worker/drawable/GPU/callback distributions, p50/p95/p99 snapshots and separate error/drop counters |
| Source preparation | One reusable generated client, exact-pin checks, selective patches, recorded file baselines and project merging that preserves signing edits |
| Reference monitor | Dashboard/transport/policy sources retained; dashboard patch excluded from the standard generated client |

The current renderer acquires the drawable before committing decode/conversion.
The presentation and shader optimizations discussed during latency investigation
are not implemented. There is no integrated Vulkan backend, partial-frame recovery,
automatic session retry or benchmark-aware PyroWave codec selection.

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
