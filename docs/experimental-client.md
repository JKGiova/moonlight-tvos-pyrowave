# Experimental live tvOS client

Moonlight Pyro adds an experimental PyroWave path to Moonlight TV. The host encodes the video and the Apple TV decodes it with Metal. The live path uses complete frames and supports 8-bit SDR 4:2:0. [Device observations](development-status.md#apple-tv-device-observations)

## Install on a physical Apple TV

1. On a Mac with Xcode and the tvOS SDK, follow the [README installation steps](../README.md#installation) to clone the repo, verify its pinned submodules and generate the client. When updating, run `git pull --ff-only` and `python3 tools/bootstrap.py`, then run `python3 tools/prepare_client.py` to update the same Xcode project. Intel Macs can compile the tvOS target. The live shader runs on the Apple TV.
2. In Xcode, configure **Signing & Capabilities** for the **Moonlight TV** target. Enable automatic signing, select your team and enter a unique bundle identifier. Use the same team and identifier when updating an existing installation. Pair the Apple TV with Xcode if needed, select it as the run destination and press **⌘R**. [Apple’s device and signing guide](https://developer.apple.com/documentation/xcode/building-and-running-an-app)
3. On the TV, open Moonlight Pyro, select the Vibeshine PC and complete the PIN pairing flow if prompted. Confirm that a standard stream works. The app list uses Moonlight’s standard layout. Stream metrics appear in **Statistics Overlay** after the session starts.
4. Open the Moonlight Pyro entry in tvOS Settings. Set **Preferred Codec → PyroWave (SDR)**, turn off HDR, select **720p** and **60 FPS**, and enable **Statistics Overlay**. Return to Moonlight Pyro and start a new stream. On A12, look for **PyroWave metal-portable-apple5**. The app can be launched from the TV Home Screen after installation without Xcode.

## Codec negotiation

The host must advertise `SCM_PYROWAVE` and exactly one `a=x-ss-pyrowave.bitstream:186f0393` attribute in RTSP DESCRIBE. The client also checks the requested profile and GPU capabilities. If a gate fails, the session negotiates a standard codec. Confirm the codec in the overlay. If the renderer fails after PyroWave negotiation, retry manually with **Preferred Codec → Auto** or **HEVC**.

The decoder factory selects `metal-portable-apple5` on A12 and can select `metal-native-apple7` on Apple7-or-later GPUs such as A15. The persistent codec setting works in Debug and Release. For a Debug-only experiment, `-PyroWaveExperimental YES` requests PyroWave when the preference is Auto. On capable devices, `-PyroWavePortable YES` selects the portable implementation for comparison when PyroWave is explicitly requested. [Apple5 decoder](apple5-decoder.md)

## Bitrate and comparison runs

Manual requests range from **0.5 to 1,000 Mbps**, with **20 Mbps** as the default for a fresh install. **Auto (by stream profile)** chooses the initial request after codec negotiation. PyroWave uses a 1.6-bit-per-pixel heuristic with a 500 Mbps cap. The host determines the applied rate. The client request is fixed for the session.

| Profile | PyroWave Auto (Mbps) | Standard codec Auto (Mbps) |
| --- | ---: | ---: |
| 720p30 | 44.2 | 5 |
| 720p60 | 88.5 | 10 |
| 1080p30 | 99.5 | 10 |
| 1080p60 | 199.1 | 20 |
| 1440p30 | 176.9 | 20 |
| 1440p60 | 353.9 | 40 |
| 4K30 | 398.1 | 40 |
| 4K60 | 500 | 80 |

For a repeatable 4K60 A12 comparison, start at a manual **150 Mbps**. Run the same scene at 150 and 200 Mbps on the same build, with the same host settings, network and test duration. Note the counters at the beginning and end of each measured interval. Record the applied bitrate when the host exposes it, plus any visible stutter or quality differences. [Vibeshine test workflow](vibeshine-testing.md)

## Memory and scheduling

`Connection.m` dispatches PyroWave decode units before NAL parameter-set processing. The renderer validates and copies the linked packet buffers before `LiCompleteVideoFrame` releases them. CPU framing validation and drawable acquisition run on a serial worker. The renderer creates two independent native decoder/texture slots, each reused only after its GPU command completes. This also keeps the upstream four-entry upload pool from blocking the UI.

The PyroWave input worker waits for complete decode units from common-c and submits them as they arrive. Standard codecs use display-link polling. At most two commands are in flight and one newest frame is pending. A new pending frame replaces the previous one under overload. There are no per-frame dispatch blocks accumulating behind the GPU, no image readback, and no GPU completion wait on the main thread. The PyroWave path bypasses the standard one-frame pacing hold. Y/Cb/Cr remain private R8 textures; compute decode and full-screen color conversion share one command buffer and present through CAMetalLayer. Limited/full-range BT.601 and BT.709 are explicit, with range taken from the negotiated session configuration; unsupported color profiles terminate the experiment instead of being displayed as SDR.

## Current transport boundary

The selective protocol patches negotiate SDR 4:2:0 PyroWave, advertise record framing, handle complete frames as opaque picture data and request additional UDP receive-buffer headroom. It retains the baseline encrypted RTP/FEC transport and standard loss handling. A damaged frame is dropped as a whole. The live adapter does not deliver Nonary `BUFFER_TYPE_LOST`, record-start flags or critical-packet metadata. It has no partial-frame recovery.

The patches derive their constants/negotiation from pinned Nonary common-c `d6a11bc685b41037b352a96f29d08276fe5359ba` and the verified Vibeshine protocol at `0689b2e021d6106612a7ed72a34dacc714b7a133`. Controller haptics and unrelated donor changes are not imported. Upstream baseline sources and licenses stay intact in submodules. The prepared app includes GPL protocol/renderer code and retains Moonlight's license; native PyroWave files retain their MIT notices.

## Statistics Overlay

| Field | What it measures |
| --- | --- |
| Video stream | Configured resolution, stream FPS estimated from frame numbers, and the negotiated codec. The FPS estimate includes missing frames. |
| Frames dropped by your network connection | Missing frames as a percentage of expected frames in the latest completed sample window. |
| Average network latency | Estimated network round-trip time and variance. |
| Host processing latency | Minimum, maximum and average host processing time when supplied by the host. |
| PyroWave | The active Metal decoder backend. |
| Ready p95 (GPU end) | The 95th percentile from renderer submission to Metal’s GPU end timestamp. Uses up to 2,048 completed frames with valid timestamps. The earlier overlay measured through the completion callback. |
| GPU/pending | Snapshot of occupied processing slots (including CPU/drawable waits) and pending frames. The queue holds two in-flight frames and one pending frame. |
| Queue drops | Cumulative number of older pending frames replaced by newer frames in the session. Compare the increase over a fixed interval. |
| Submit to worker / Drawable wait / GPU / Callback delay | Separate p95 values in milliseconds. These cover renderer entry to mailbox pickup (including validation/copy and scheduling), drawable acquisition, GPU execution for decode plus conversion, and GPU end to entry into the completion callback. |
| Parser rejects | Cumulative frames rejected by framing validation. |
| Decode failures | Cumulative failures reported by the renderer while processing frames. |
| Present drops | Cumulative frames dropped because a Metal drawable was unavailable. |

Ready p95 covers completed frames. Use the drop counters alongside it to see how often work was skipped. GPU decode, visual presentation and controller-to-screen latency require their own timing boundaries. The renderer records GPU decode plus color conversion timing internally when valid command-buffer timestamps are available. [Performance measurement guide](decoding-performance.md)

The renderer still acquires its drawable before submitting GPU decode/conversion.
The timing breakdown documents this behavior; it does not demonstrate that the
presentation bottleneck has been removed. Percentiles are calculated separately
and cannot be added to obtain Ready p95. No physical on-screen timing is recorded.
