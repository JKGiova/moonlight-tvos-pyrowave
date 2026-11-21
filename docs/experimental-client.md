# Experimental live tvOS client

The implementation connects PyroWave to the genuine Moonlight TV target through selective, reviewable patches. It is not a release-qualified codec. The earlier integrated unsigned ARM64 target and presenter pipeline compiled in [CI](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37654083647). The user reports standard streaming working on A12/tvOS 27 with Xcode 26.6/SDK 26.5. A reported A12 smoke test streamed PyroWave at 4K60 and 150 Mbps for 30 minutes with zero queue drops and a Ready p95 of about 60 ms. Controlled visual and latency measurements are still pending. The new app is named **Moonlight Pyro** and includes an experimental Apple5 decoder.

The new [Apple5 CI run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37809452393) also passed unsigned tvOS compilation, GPU coefficient checks and full synthetic decoder reconstruction. Prepare a fresh project before repeating the device test.

## Build and select a development session

On a Mac, initialize dependencies and prepare/build the integrated client:

```sh
git pull --ff-only
python3 tools/bootstrap.py
python3 tools/prepare_client.py --client-dir build/client/Moonlight-apple5
```

Use a fresh directory if `Moonlight-apple5` already exists with older inputs; the tool preserves your previous generated checkout and signing edits. Open `build/client/Moonlight-apple5/Moonlight.xcodeproj`, select **Moonlight TV** and the paired physical TV, and copy the same Team and unique Bundle Identifier you used for the working build. Build/install with Run. The earlier generated project is not automatically updated. Intel macOS with Xcode 26.6/SDK 26.5 can compile this app; the runtime shader executes on the Apple TV.

To test without launch arguments, select **PyroWave (Experimental SDR)** under **Preferred Codec** on the TV. This preference persists across app launches and applies to Debug and Release builds. Disable HDR and start at 720p60, 8-bit SDR 4:2:0. Keep your chosen bitrate. Pair manually with Vibeshine if needed. Disconnect the Xcode debugger before rebooting the dual-boot PC into Windows; launch Moonlight Pyro from the TV and connect to Vibeshine. Xcode does not need to stay open.

Normal **Auto** still negotiates standard hardware codecs. The alternative Debug launch arguments `-PyroWaveExperimental YES` request an experiment only when Auto is selected; Release ignores these arguments. Manual HEVC/H.264/AV1 choices keep their original behavior. No credentials or PC addresses are stored in the repository.

The decoder-only factory chooses `metal-portable-apple5` on A12 and `metal-native-apple7` on Apple7+ devices such as A15, after real pipeline/resource checks. The original native encoder/device API gate stays intact. A supported family permits an experiment, not qualification. The host must advertise `SCM_PYROWAVE` and exactly one line `a=x-ss-pyrowave.bitstream:186f0393` in RTSP DESCRIBE. Missing, duplicated or mismatched identity lines preserve standard HEVC/H.264 negotiation. Unsupported device/host/SDR geometry or HDR requests also preserve the standard codec mask and log a refusal. Always verify the actual negotiated codec in the overlay. Shader/decoder setup failure rejects startup; automatic retry is not implemented. If startup fails, select Auto or HEVC for the next launch.

For native/portable comparison on A15, add the Debug arguments `-PyroWavePortable YES` while explicitly requesting PyroWave. A12 already chooses the portable backend and needs no such argument. See [Apple5 decoder checks](apple5-decoder.md).

Start with 720p60 and record the bitrate applied by the host. The Bitrate menu supports manual requests through 1000 Mbps (including 600, 700, 800 and 900 Mbps). Auto (by stream profile) selects an initial target from resolution, frame rate and negotiated codec. For PyroWave SDR it uses a 1.6-bit-per-pixel heuristic, capped at 500 Mbps. This is an initial request and the required bitrate varies with the content and desired quality. The reported 4K60 smoke test used a manual 150 Mbps setting. For standard codecs it uses the conventional Moonlight targets. The host applies its own rate control. The tvOS app list uses the standard Moonlight layout and Statistics Overlay remains available during streaming. The generated-video script is still available for real offline encoding and reconstruction checks before live testing.

## Memory and scheduling

`Connection.m` dispatches PyroWave decode units before NAL parameter-set processing. The renderer validates and copies the linked packet buffers before `LiCompleteVideoFrame` releases them. CPU framing validation and drawable acquisition run on a serial worker. The renderer creates two independent native decoder/texture slots, each reused only after its GPU command completes. This also keeps the upstream four-entry upload pool from blocking the UI.

At most two commands are in flight and one newest frame is pending. A new pending frame replaces the previous one under overload. There are no per-frame dispatch blocks accumulating behind the GPU, no image readback, and no GPU completion wait on the main thread. The PyroWave path bypasses the standard one-frame pacing hold. Y/Cb/Cr remain private R8 textures; compute decode and full-screen color conversion share one command buffer and present through CAMetalLayer. Limited/full-range BT.601 and BT.709 are explicit, with range taken from the negotiated session configuration; unsupported color profiles terminate the experiment instead of being displayed as SDR.

## Current transport boundary

The first selective protocol patch negotiates SDR 4:2:0 PyroWave, advertises record framing, handles complete frames as opaque picture data and requests additional UDP receive-buffer headroom. It retains the baseline encrypted RTP/FEC transport and standard loss handling. A damaged frame is dropped as a whole. It does **not** yet deliver Nonary `BUFFER_TYPE_LOST`, record-start flags or critical-packet metadata; partial recovery, precise reassembly deadlines and Darwin receive-loop tuning are separate work.

The patches derive their constants/negotiation from pinned Nonary common-c `d6a11bc685b41037b352a96f29d08276fe5359ba` and the verified Vibeshine protocol at `0689b2e021d6106612a7ed72a34dacc714b7a133`. Controller haptics and unrelated donor changes are not imported. Upstream baseline sources and licenses stay intact in submodules. The prepared app includes GPL protocol/renderer code and retains Moonlight's license; native PyroWave files retain their MIT notices.

## Diagnostics and next gates

The statistics overlay exposes queue occupancy/replacements, parser rejects, GPU failures, drawable drops and a completion-based client-ready p95 proxy. Network loss stays in the original network counter. The renderer's statistics also provide rolling p50/p95/p99, up to 2,048 samples. Valid command-buffer timestamps cover **decode plus color conversion**, not decoder-only latency; decoder-only metrics remain null. Completion timing is a proxy and includes scheduling, so it cannot qualify normal Auto or be compared against hardware enqueue time.

The overlay now also names the backend; on A12 it must show **PyroWave metal-portable-apple5**. If it shows HEVC/H.264, the PyroWave decoder is not being tested. Record the scene, TV model/OS, host version/settings, profile/bitrate and the counters after warm-up; start with five minutes at 720p60 before moving to 1080p60.

Still required: physical A12/A15 visual/live tests, full saved-frame native/portable comparison, partial-frame recovery, separate GPU-stage measurements and observed presentation timing, qualified normal codec Auto and one-shot session fallback. A passing build or Mac coefficient test does not establish those results.
