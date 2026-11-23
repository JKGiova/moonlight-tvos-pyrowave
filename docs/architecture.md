# Runtime architecture

The PC host encodes. The tvOS app negotiates the stream, receives complete frames,
and decodes and presents PyroWave using native Metal.

| Component | Current responsibility |
| --- | --- |
| Pinned Moonlight app | Host/app UI, pairing, settings, audio/input and standard codecs |
| Selective common-c patches | PyroWave capability/SDP, bitstream checks and complete-frame transport integration |
| PyroWave receive worker | `LiWaitForNextVideoFrame`, renderer submission and `LiCompleteVideoFrame` |
| `native/protocol/pyrowaveframing.*` | Framing, geometry and payload validation |
| `native/client/latest_frame_queue.hpp` | Two occupied processing slots and one replaceable pending frame |
| `native/apple/PyroWaveVideoRenderer.mm` | Frame ownership, serial worker, Metal command encoding, completion and statistics |
| Generated PyroWave Metal sources | Portable/native decoder factory, dequantization, inverse wavelet transform and texture allocation |
| Presenter in the renderer | YUV-to-RGB conversion and CAMetalLayer presentation |
| Reference dashboard sources | Optional host monitor implementation, outside the standard generated UI |

## Source preparation

`tools/prepare_client.py` checks exact upstream revisions and nested dependencies,
applies selected patches and updates the reusable project below
`build/client/Moonlight-Clean-Release/`, preserving local signing and Xcode user data. `tools/prepare_metal.py` stages the pinned Metal sources plus the
Apple5 patch. Source submodules stay pristine. [Patch list](../integration/README.md)

## Ownership and scheduling

The renderer copies a common-c decode unit before common-c releases it. A serial
worker picks the newest pending frame, validates/parses its packets and commits
GPU decode. It then acquires a drawable from a three-resource pool and submits
conversion/presentation on the same Metal command queue. Tracked plane textures
carry dependencies between the two command buffers. Slot release requires both
decode completion and conversion completion or presentation abandonment.

There are two independent decoder/output-texture slots and at most one pending
frame. New arrivals replace older pending frames. Occupied slots include work
waiting for a drawable. The overlay calls this `Slots/pending`. GPU callbacks retain the runtime until submitted work finishes.

Layer setup/removal runs on the main thread. Drawable acquisition runs on the
worker. The live renderer has no image readback or main-thread GPU completion wait.
The receive worker is separate from the serial decode worker. [Timing boundaries](decoding-performance.md)

## Current boundaries

The live path is complete-frame, 8-bit SDR 4:2:0. Hardware/profile/host checks gate
manual PyroWave requests; codec Auto remains Moonlight's standard path. There is
no benchmark store, benchmark-aware Auto selector, automatic session fallback or
partial-frame recovery in the integrated client.
