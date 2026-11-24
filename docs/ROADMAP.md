# Roadmap

Updated 2026-11-24. This is the next-work plan, not a release-date promise.
For what is already built, see [the implementation record](PLAN.md).
For measurements and their limits, see [practical tests](practical-tests.md).

## 1. Verify HDR10 and 4:4:4 in real streams

The client paths exist and offscreen checks pass. Next, connect a real Vibeshine
host and a compatible TV: check SDR/HDR switching, colored desktop text, dark and
bright scenes, session restart, and a 30-minute session. Test 4:2:0 and 4:4:4,
8-bit SDR and 10-bit HDR10 separately. Confirm the host's actual format and TV
output mode, rather than relying only on the client's settings or overlay.

Done when the recorded session has the requested profile, correct visible colors
and HDR mode, no parser/decode/presentation errors, bounded queues, and documented
counter changes. If drops occur, record their rate and conditions. A successful
short offscreen test does not complete this step. Requires the host PC to be on.

## 2. Measure latency and stability in a fair comparison

Compare PyroWave and HEVC on the same device, scene, resolution, frame rate and
network route. Record requested/applied bitrate and image-quality differences;
the same bitrate does not imply the same quality. Use repeat runs, timing
percentiles and counter deltas. If the question is controller-to-screen delay,
measure it externally with a high-speed camera or equivalent instrumentation.

Exercise 720p, 1080p and 4K at 60 FPS, with budgets through 1,000 Mbps when the
host and link can deliver them. Separate host encoding, network, client work and
TV processing. Optimize a measured bottleneck, then repeat the same workload
without reducing resolution, frame rate, chroma or bit depth.

Done when a reproducible comparison and long-session drop rates are published.
An overlay Ready value, serial offline processing time or simulator result alone
is insufficient to claim lower end-to-end latency than HEVC.

## 3. Qualify more devices before changing codec Auto

Repeat correctness, real-stream and performance checks on each supported model
and backend, including the A15 variants. Keep one app and one reusable Xcode
project. Record the device, OS and profile with each result; an A12 result is not
an A15 result. Broader device coverage precedes benchmark-aware codec Auto.

Done when model/profile evidence supports explicit admission criteria and a safe
failure path. Until then, codec Auto retains the standard Moonlight selection.
Bitrate Auto is a separate existing feature.

## 4. Extend the host protocol for HDR10+

HDR10+ needs per-frame dynamic metadata, which the inspected Vibeshine protocol
does not transport. Establish a real metadata source first, then version and
negotiate the transport, associate metadata with its frame, validate it, and
attach it to the client's sample. Test on an HDR10+-capable Apple TV and TV; the
current second-generation A12 is not the qualification device for that output.

Done when genuine dynamic metadata reaches the correct frames and physical HDR10+
output is validated. Do not rename HDR10 as HDR10+ or synthesize a support claim.
Requires host-side work and compatible hardware. [Current color profile guide](video-profiles.md)
