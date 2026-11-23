# Metal integration

`third_party/pyrowave` is the pinned native codec dependency. Generated sources
include the decoder-only Apple5 patch, portable dequantizer and native
Apple7-or-later candidate. The encoder retains its original Apple7 gate.

`native/apple/PyroWaveVideoRenderer.mm` owns two decoder/private-texture slots,
one replaceable pending frame, GPU color conversion and CAMetalLayer presentation.
Decode commits before drawable acquisition; conversion uses a second command buffer on the same queue. Both stages resolve before an app slot is reused. There is no live image readback.
The Apple5 shader is embedded from its source and checked by CI.

`tools/pyrowave_video.mm` provides offline encode/decode and readback for tests.
The presenter source is shared with its offscreen correctness checker. No Vulkan
or MoltenVK backend is integrated. [Decoder details](../../docs/apple5-decoder.md),
[timing](../../docs/decoding-performance.md) and [evidence](../../docs/development-status.md).
