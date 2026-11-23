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
| Renderer | Two decoder/texture slots, latest-frame mailbox, decode before drawable acquisition, separate conversion and three-drawable presentation |
| Frame delivery | PyroWave receive worker waits for complete frames from common-c instead of display-link polling |
| Settings | Persistent PyroWave (SDR), manual bitrate through 1,000 Mbps and per-profile bitrate Auto |
| Diagnostics | GPU-end Ready, decode/conversion/queue distributions, frame timestamps, device presentation observations and separate loss/error counters |
| Offline tools | Video generation, real encoding, frame validation, Metal decode/readback and comparison reports |
| Automated checks | Portable parser/runtime tests, GPU fixture/presenter checks and unsigned tvOS builds in CI |
| Reference dashboard | Retained dashboard/monitor sources and optional integration patch; excluded from the standard generated app |

The renderer commits decode before drawable acquisition and submits conversion
separately on the same command queue. Slot ownership covers both stages, including
presentation abandonment. The shader pipeline retains its existing implementation.
Physical A12 timing for this scheduling revision remains to be collected.

The application and protocol pins, local patches and license provenance are in
[upstream import](upstream-import.md) and the [dependency manifest](../configs/upstreams.lock.json).
