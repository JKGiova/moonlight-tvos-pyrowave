# Metal integration boundary

Planned changes: pinned PyroWave native Metal dependency, portable Apple5 dequantization for A12, native Apple7-or-later candidate for A15, offline harness, texture pool and GPU presentation. Select the backend through actual capability and pipeline checks; qualify correctness and latency on physical devices per model/backend/profile. No model is qualified yet. See [device support](../../docs/device-support.md) and [decode performance](../../docs/decoding-performance.md).

The real pinned source is registered at third_party/pyrowave. tools/pyrowave_video.mm implements offline C-API encode/decode, built by tools/build_engine.py. It currently preserves the upstream Apple7 gate; no Apple5 support or physical-device performance claim is made.

The experimental live decoder/presenter now lives in native/apple/PyroWaveVideoRenderer.mm. It reuses two private-texture/decoder slots, keeps only one latest pending frame and performs GPU color conversion on the same command buffer without CPU image readback. The actual presenter shader is shared with tools/check_presenter_shader.mm for real Metal pipeline compilation checks. See [experimental client testing](../../docs/experimental-client.md).
