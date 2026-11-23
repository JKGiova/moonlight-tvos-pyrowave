# Implementation record

This page records completed implementation work. Runtime behavior is described in
[the Apple TV guide](experimental-client.md); test evidence is recorded in
[development status](development-status.md).

| Area | Implemented |
| --- | --- |
| App baseline | Pinned Moonlight iOS/tvOS source, original Xcode project, bootstrap and generated client preparation |
| Metal dependency | Pinned PyroWave source with a decoder-only Apple5 patch applied to generated copies |
| Protocol | Selective common-c capability/SDP negotiation and complete-frame delivery; exact `186f0393` bitstream validation |
| Apple5 decoder | Threadgroup-based portable dequantizer, capability/pipeline checks and backend identification |
| Renderer | Two decoder/texture slots, latest-frame mailbox, GPU color conversion and CAMetalLayer presentation |
| Frame delivery | PyroWave receive worker waits for complete frames from common-c instead of display-link polling |
| Settings | Persistent PyroWave (SDR), manual bitrate through 1,000 Mbps and per-profile bitrate Auto |
| Diagnostics | GPU-end Ready timing, separate worker/drawable/GPU/callback distributions and separate loss/error counters |
| Offline tools | Video generation, real encoding, frame validation, Metal decode/readback and comparison reports |
| Automated checks | Portable parser/runtime tests, GPU fixture/presenter checks and unsigned tvOS builds in CI |
| Reference dashboard | Retained dashboard/monitor sources and optional integration patch; excluded from the standard generated app |

The renderer still acquires a drawable before submitting decode and conversion
on one command buffer. The shader and presentation optimizations discussed during
latency analysis are not implemented. No Vulkan/MoltenVK backend is integrated.

The application and protocol pins, local patches and license provenance are in
[upstream import](upstream-import.md) and the [dependency manifest](../configs/upstreams.lock.json).
