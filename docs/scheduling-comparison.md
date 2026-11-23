# PyroWave scheduling comparison

Reviewed on 2026-11-23 against Moonlight Pyro at `aee0123872a4186f327df534e23530bb520efd85`,
Nonary Moonlight Qt at `9184cacd8d426316bdecc47634f0dbf4e6e34654`, and
Pyrolight at `561bd3cad2d15ae74b01b4faadc03caa6868061d`.
The Nonary snapshot is its current default-branch implementation, newer than
the `1ad5848b` framing donor pinned by this project. Pool sizes below describe
resource bounds. Device timing comparisons require matching workloads and hardware.
[Local dependency references](../configs/upstreams.lock.json),
[Nonary snapshot](https://github.com/Nonary/moonlight-qt/tree/9184cacd8d426316bdecc47634f0dbf4e6e34654),
[Pyrolight snapshot](https://github.com/karsyboy/Pyrolight/tree/561bd3cad2d15ae74b01b4faadc03caa6868061d)

## Implementation update

The tvOS code now implements decode submission before drawable acquisition,
separate conversion on the same command queue, three drawable resources, retained
frame metadata and independent GPU timing for decode and conversion. Both stages
resolve before a processing slot is reused. The analysis below records the earlier
local snapshot and the rationale for those changes. Physical A12 measurements will
determine their effect. [Current timing and scheduling](decoding-performance.md)

## Compared paths

| Concern | Moonlight Pyro tvOS | Nonary Moonlight Qt | Pyrolight |
| --- | --- | --- | --- |
| Input delivery | Dedicated common-c pull worker | Decoder thread waits for common-c input | Direct-submit callback hands off a latest encoded frame |
| GPU admission | Two occupied decoder/texture slots, one replaceable encoded pending frame | Four codec frame contexts; separate output surfaces and pacing queues | Fixed path has active work plus latest encoded pending; VRR adds decoded output buffering |
| Decode versus display wait | Acquire drawable, then submit decode and conversion together | Submit asynchronous decode to shared surfaces, then observe per-frame readiness and prepare presentation | Submit decode before presentation-capacity wait; VRR prepares an intermediate image ahead of presentation |
| Overflow handling | Replace pending encoded frame | Bounded queues, oldest-frame eviction and age-aware shedding | Replace encoded pending; VRR also evicts oldest waiting decoded frame |
| Presentation target | Immediate command-buffer present, layer scheduling | Fixed pacing or RTP-based adaptive worker | Fixed rendering thread or RTP-based adaptive worker |
| Current timing | Renderer entry to GPU end; combined decode and conversion | Delivery timeline, decode dependencies, pacing and backend presentation observations | Submission, processing, GPU dequant/iDWT diagnostics and VRR preparation/presentation counters |

The following sections provide source references and the conditions behind each row.

## Moonlight Pyro on tvOS

The receive worker uses `LiWaitForNextVideoFrame` and completes each handle after
copying the payload. The renderer copies under its shared lock into a new allocation,
then stores the frame in its latest-frame mailbox. The decode pump runs on a serial
dispatch queue. Its explicit order is framing validation, codec packet preparation,
`nextDrawable`, command-buffer encoding, presentation request, then commit.
The completion callback releases the occupied slot.
[Receive worker](../integration/patches/moonlight-pyrowave-scheduling.patch),
[Renderer](../native/apple/PyroWaveVideoRenderer.mm),
[Mailbox](../native/client/latest_frame_queue.hpp)

The layer has two drawable resources. The two processing slots also cover CPU
preparation and drawable waiting. Once `take()` removes a frame from pending,
new arrivals can replace only its pending successor. A drawable wait can therefore
hold an older active frame while newer pending frames replace one another. On
resumption, the active frame proceeds without another age check. Its stored
metadata includes a local arrival time and color information; RTP timestamps and
frame numbers are available in the incoming decode unit but are discarded by
this renderer's frame representation.
[Layer and frame representation](../native/apple/PyroWaveVideoRenderer.mm),
[Mailbox selection and replacement](../native/client/latest_frame_queue.hpp)

The common-c pull queue is a separate boundary with capacity 15 in the pinned
baseline. Our renderer's two-plus-one limit applies downstream of that queue.
Slow payload copying or contention with completion/statistics can delay draining
it. Actual residence at that boundary needs measurement. Ready starts at renderer
entry, after the common-c wait, and therefore covers the subsequent local work.
[Common-c queue](https://github.com/moonlight-stream/moonlight-common-c/blob/f900dd4767759c7b9d0e93bcea666b55c69ea62f/src/VideoDepacketizer.c#L55-L69),
[Timing boundaries](decoding-performance.md)

The codec itself has four upload slots per decoder instance, reclaimed using the
consuming command buffer. Our app supplies two independent decoder instances and
releases each app slot only after completion. The internal upload ring capacity
therefore differs from the app's limit on occupied processing slots.
[Codec upload slots](../third_party/pyrowave/metal/pyrowave_decoder.mm),
[App slot ownership](../native/apple/PyroWaveVideoRenderer.mm)

## Nonary Moonlight Qt

The current decoder requests four codec frame contexts, and its shared-output
path submits GPU work with acquire/release synchronization before handing an
AVFrame to the pacer. On macOS, MoltenVK decodes into up to eight shared plane
surfaces that native Metal samples directly. This is a different backend and
resource arrangement from our native Metal Apple5 decoder.
[Codec contexts](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/pyrowave/pyrowavedecoder.cpp#L396-L416),
[Shared-output submission](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/pyrowave/pyrowavedecoder.cpp#L532-L571),
[Metal surface ownership](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/pyrowave/pyrowavemetal.mm#L337-L424)

Before decoding, Nonary can skip a frame that has spent over two source periods
in the input queue when a newer frame is available. It derives cadence from RTP
movement and keeps delivery timestamps through the pacing handoff. It also has
a bounded decode hold around a pending presentation window to reduce competition
for GPU resources at that point.
[Input age policy](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg.cpp#L3180-L3214),
[Decode hold](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg.cpp#L3321-L3339),
[Delivery handoff](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg.cpp#L2993-L3018)

The legacy pacer bounds each of its enqueue queues at three frames. Its adaptive
worker uses a separate capacity policy, default three waiting frames and configurable
up to four. The adaptive worker evicts the oldest waiting frame at capacity and
checks frame age against timing policy. These capacities refer to different stages.
[Legacy bound](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp#L536-L559),
[Adaptive admission](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/pacer/vrrpacingworker.cpp#L239-L298),
[Adaptive bounds](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/pacer/vrr/vrrtypes.h#L15-L20)

Its macOS adaptive path observes decode readiness, acquires a drawable, renders,
waits for render completion with a 50 ms bound, and then schedules the prepared
drawable. The layer uses three drawables, explicitly to keep the displayed image
and submitted successor from blocking preparation. Presented handlers retain
OS presentation timestamps separately from GPU/CPU completion.
[Readiness](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/vt_metal.mm#L681-L701),
[Preparation](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/vt_metal.mm#L722-L791),
[Drawable pool](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/vt_metal.mm#L1070-L1081),
[Presentation evidence](https://github.com/Nonary/moonlight-qt/blob/9184cacd8d426316bdecc47634f0dbf4e6e34654/app/streaming/video/ffmpeg-renderers/vt_metal.mm#L799-L834)

## Pyrolight

Pyrolight advertises direct-submit. Its callback copies and, for negotiated record
framing, also parses/compacts/unpacks the input before handing off an encoded
frame. The fixed path uses a dedicated high-priority rendering thread and one
latest encoded pending slot. It submits decode before waiting for presentation
capacity. A selected active frame stays active while new arrivals replace pending
work, so this path also permits an active frame to age during presentation waiting.
[Input adaptation](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L453-L510),
[Decode ordering](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L758-L768),
[Active-frame ownership](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L938-L1000)

Its VRR path separates decoding from pacing. A latest encoded mailbox feeds a
decode thread, which hands plane sets to the pacing worker. The pool grows on demand to at most six
plane sets. The pacing queue holds four waiting decoded frames plus active work,
evicts the oldest waiting frame on overflow, and sheds stale waiting frames when
a newer successor exists. Successfully prepared frames proceed to presentation
even when late, preserving progress under load.
[Decode handoff and plane sets](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L772-L850),
[Queue limits](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/ffmpeg-renderers/pacer/vrr/vrrtypes.h#L16-L19),
[Admission and stale handling](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/ffmpeg-renderers/pacer/vrrpacingworker.cpp#L100-L213),
[Prepared-frame progress](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/ffmpeg-renderers/pacer/vrrpacingworker.cpp#L277-L316)

Timeline semaphores order codec writes and libplacebo reads. The VRR preparation
path normally renders into an intermediate image, observes completion with a
50 ms bound, and acquires the presentation target later. Its `readyUs` at decode
handoff records submission return. The decode-call duration and the VRR field
wrapping full `decodeToPlanes` also have different CPU timing boundaries.
Cross-client comparisons must align these boundaries with actual GPU completion.
[Timeline ownership](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L674-L707),
[Handoff timestamp](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/pyrowave.cpp#L821-L850),
[Offscreen preparation and presentation](https://github.com/karsyboy/Pyrolight/blob/561bd3cad2d15ae74b01b4faadc03caa6868061d/app/streaming/video/ffmpeg-renderers/plvk.cpp#L1399-L1553)

## Experiments suggested by the comparison

1. Preserve frame number, RTP time and common-c timestamps in our frame metadata.
   Record input queue residence, CPU parse/upload, commit-to-GPU-start, decode-only
   GPU time, conversion and OS presentation observations. Keep replacement/drop
   reasons and frame identifiers with the timing samples.
2. Compare two and three drawable resources while holding the app's occupied-slot
   limit at two. The Nonary macOS correction supplies a concrete hypothesis for
   our observed drawable wait. A12 measurements must establish its effect on
   frame age, cadence, memory and visual presentation.
3. Submit decode before drawable acquisition with a bounded decoded-frame handoff.
   Keep decoder textures owned until the conversion read completes. This enables
   overlap of decode with display waiting, as in both reference architectures.
   Compare against the current single-command-buffer path before adopting it.
4. Add age-aware admission using source cadence and the presence of a newer
   successor. Preserve forward progress for already-ready output during overload.
   Nonary and Pyrolight both explicitly account for starvation risks in their
   post-decode policies.
5. Profile Apple5 shader work after scheduling boundaries are observable. The
   recorded 22.32 ms GPU p95 combines decode and conversion; it cannot attribute
   cost to a single shader or establish steady-state throughput.
   [Current device observations](development-status.md#apple-tv-device-observations)

## Local verification and remaining measurements

A scratch C++ replay compiled against our actual `LatestFrameQueue` took frame 1,
submitted frames 2 and 3 while holding frame 1, and checked that frame 1 remained
active, frame 3 became its successor, and one pending replacement was counted.
The result confirms mailbox ownership semantics. Source inspection establishes
the drawable-before-decode ordering.

This review changes documentation. Physical A12 tests will determine whether
the proposed scheduling changes reduce the observed waits. The existing screenshots
supply separate p95 values from different timing distributions. A comparison of
visible latency across these clients requires matched host settings, scene, profile,
network, presentation mode and measurement boundaries.
