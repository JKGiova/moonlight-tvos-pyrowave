# Experimental live tvOS client

The implementation connects PyroWave to the genuine Moonlight TV target through selective, reviewable patches. It is not a release-qualified codec. The integrated unsigned ARM64 target and the actual presenter shader/render pipeline compiled successfully in [CI](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37654083647). Real host/device streaming, visual correctness, loss behavior, restart/fallback and latency remain untested.

## Build and select a development session

On a Mac, initialize dependencies and prepare/build the integrated client:

```sh
python3 tools/bootstrap.py
python3 tools/build_tvos.py --sdk appletvos
```

Open `build/client/Moonlight/Moonlight.xcodeproj` and configure your local signing team and a unique persistent bundle ID. For a Debug build, add the Xcode scheme launch arguments `-PyroWaveExperimental YES`. Keep the normal codec preference at Auto, disable HDR, choose 8-bit SDR 4:2:0 and a supported geometry from 128x128 through 4096x2160. Perform normal manual PIN pairing with the selected Vibeshine host. This argument is an explicit experimental request, not normal Auto admission; manual HEVC/H.264/AV1 preferences are respected. Release builds ignore the argument. No credentials or PC addresses are stored in the repository.

The original native Apple7 support gate stays intact: A12/Apple5 is not enabled yet. A supported family permits an experiment, not a performance/correctness qualification. The host must advertise `SCM_PYROWAVE` and exactly one line `a=x-ss-pyrowave.bitstream:186f0393` in its RTSP DESCRIBE response. Missing, duplicated or mismatched identity lines preserve standard HEVC/H.264 negotiation. Shader/decoder setup failure rejects startup; automatic retry/reconnection after that failure is not implemented yet.

Start with 720p60 and record the actual configured host bitrate. The app preserves the selected bitrate; it does not inflate it or reduce resolution/quality to admit PyroWave. The generated-video script is still available for real offline encoding and reconstruction checks before live testing.

## Memory and scheduling

`Connection.m` dispatches PyroWave decode units before NAL parameter-set processing. The renderer validates and copies the linked packet buffers before `LiCompleteVideoFrame` releases them. CPU framing validation and drawable acquisition run on a serial worker. The renderer creates two independent native decoder/texture slots, each reused only after its GPU command completes. This also keeps the upstream four-entry upload pool from blocking the UI.

At most two commands are in flight and one newest frame is pending. A new pending frame replaces the previous one under overload. There are no per-frame dispatch blocks accumulating behind the GPU, no image readback, and no GPU completion wait on the main thread. The PyroWave path bypasses the standard one-frame pacing hold. Y/Cb/Cr remain private R8 textures; compute decode and full-screen color conversion share one command buffer and present through CAMetalLayer. Limited/full-range BT.601 and BT.709 are explicit, with range taken from the negotiated session configuration; unsupported color profiles terminate the experiment instead of being displayed as SDR.

## Current transport boundary

The first selective protocol patch negotiates SDR 4:2:0 PyroWave, advertises record framing, handles complete frames as opaque picture data and requests additional UDP receive-buffer headroom. It retains the baseline encrypted RTP/FEC transport and standard loss handling. A damaged frame is dropped as a whole. It does **not** yet deliver Nonary `BUFFER_TYPE_LOST`, record-start flags or critical-packet metadata; partial recovery, precise reassembly deadlines and Darwin receive-loop tuning are separate work.

The patches derive their constants/negotiation from pinned Nonary common-c `d6a11bc685b41037b352a96f29d08276fe5359ba` and the verified Vibeshine protocol at `0689b2e021d6106612a7ed72a34dacc714b7a133`. Controller haptics and unrelated donor changes are not imported. Upstream baseline sources and licenses stay intact in submodules. The prepared app includes GPL protocol/renderer code and retains Moonlight's license; native PyroWave files retain their MIT notices.

## Diagnostics and next gates

The statistics overlay exposes queue occupancy/replacements, parser rejects, GPU failures, drawable drops and a completion-based client-ready p95 proxy. Network loss stays in the original network counter. The renderer's statistics also provide rolling p50/p95/p99, up to 2,048 samples. Valid command-buffer timestamps cover **decode plus color conversion**, not decoder-only latency; decoder-only metrics remain null. Completion timing is a proxy and includes scheduling, so it cannot qualify normal Auto or be compared against hardware enqueue time.

Still required: physical A15 visual/live tests, A12 shader adaptation, partial-frame recovery, separate GPU-stage measurements and observed presentation timing, qualified normal Auto, one-shot session fallback and the five-second host monitor. A passing build does not establish any of those results.
