# Automatic codec selection contract

Status: proposed client behavior; no selector implementation exists.

## Responsibilities

The host PC encodes. The tvOS client chooses a codec and profile, negotiates the host capability and binds the matching local decoder to the negotiated format. There is no client-side encoder.

The inspected standard client currently sets a supported-format mask in MainFrameViewController.m. Auto includes HEVC if hardware decoding is supported, then H.264. Adding a UI enum alone does not make PyroWave the negotiated codec: common-c RTSP precedence and profile masks must agree with the policy.

## Modes

| Mode | Planned behavior |
| --- | --- |
| Auto (default) | Prefer qualified PyroWave; otherwise choose a supported fallback |
| PyroWave | Explicit request; capability/compatibility checks still apply; explain refusal |
| HEVC / H.264 / AV1 | Respect the selected family; do not override it with PyroWave |

Manual selection preserves user intent. Auto never silently changes requested HDR, chroma, resolution or frame rate merely to admit PyroWave.

## Auto admission

PyroWave is eligible only if every required gate passes:

1. Its real Metal backend has passed compilation, numerical correctness and device qualification. A12/Apple5 is currently unqualified.
2. The host advertises the exact codec/profile and compatible bitstream identity.
3. The decoder/presenter supports the requested width, height, FPS, chroma, bit depth and transfer function.
4. A valid physical-device benchmark for the matching profile/build/precision passes the latency, throughput and thermal gates.
5. The current network route has sufficient measured useful throughput with 20% headroom and live UDP burst validation. Link speed or a bulk probe alone is insufficient.
6. No applicable startup/session failure is under cooldown.

A failed or unknown gate is not success. On a cache miss, run bounded calibration before PyroWave admission; if calibration is unavailable or fails, choose a known-supported hardware codec for that session.

## Preference and ranking

Qualified PyroWave is first choice, subject to the performance gates in decoding-performance.md. When comparable full client-ready timings exist, PyroWave may regress no more than 0.5 ms p95 against the best qualifying hardware fallback. This margin is a provisional policy value to validate on hardware.

Rank qualifying fallback codecs by measured client-ready p95, then p99, with a stable tie break. Do not encode an unconditional AV1-first rule: supported hardware and requested profiles differ by device. When measurements are unavailable, preserve the standard device-capability fallback (HEVC then H.264 for the initial A12 SDR target); AV1 is admitted only with actual support.

The AVSampleBufferDisplayLayer path may conceal hardware decode timing. Queue/enqueue duration is not a decode measurement. If a cross-codec metric is not comparable, mark it unavailable and use a documented physical-device profile qualification with comparable presentation observations. Do not numerically rank a GPU decode time against a hidden hardware enqueue time.

## Negotiation

Before launch, compute the allowed-format mask from eligibility and the user's mode. For qualified Auto/PyroWave include VIDEO_FORMAT_PYROWAVE and fallback formats; common-c must give eligible PyroWave precedence. Validate server capabilities first and bind a renderer to the format actually negotiated, not the preferred setting.

Check bitstream identity during the RTSP handshake. Initially require 186f0393 or an explicitly tested compatible identity. A mismatch after preflight triggers a single fallback session with PyroWave removed from the allowed mask.

Never include unsupported PyroWave HDR/4:4:4 bits simply because the host advertises them.

## Cache and failure lifecycle

Cache key includes SoC/device, tvOS, application/codec/shader revisions, precision, profile, FPS, workload class, presenter and measurement method. Invalidate after relevant build/OS changes or measured thermal regression. Network qualification is route-specific and refreshed separately.

Record selected codec, rejected candidates and reasons, measured versus unavailable metrics, gate values and fallbacks. Planned reason codes include device_unqualified, profile_unsupported, host_unsupported, bitstream_mismatch, benchmark_missing, decode_over_budget, network_unqualified and recent_session_failure.

Keep a codec fixed for the session. Persistent overload or incompatible startup ends the session and renegotiates a fallback; do not silently send a different codec to the current decoder. Initially allow one fallback attempt per launch, disable PyroWave for the retry and suppress automatic retry on the next launch until the cooldown or recalibration condition is satisfied.

## Planned acceptance scenarios

Qualified PyroWave wins Auto; absent host support falls back; an unqualified A12 never claims success; a missing benchmark calibrates or falls back; manual HEVC stays HEVC; an HDR request never becomes SDR; protocol mismatch reconnects once; overload does not create a retry loop.

Policy examples are in ../configs/codec-policy.example.json and are specification data only.
