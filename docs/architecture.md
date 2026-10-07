# Proposed architecture

Status: responsibility boundaries, not an implemented system.

| Component | Owns | Does not own |
| --- | --- | --- |
| CodecSelectionPolicy | Candidate eligibility, PyroWave preference, fallback decision | GPU decode or host encoding |
| DecoderCapabilityProbe | Device/pipeline/profile qualification | Optimistic model-name support claims |
| DecoderBenchmarkStore | Versioned physical-device measurements and invalidation | Synthetic results |
| common-c protocol integration | RTSP/SDP, transport, reassembly and loss metadata | UI preference or renderer internals |
| PyroWaveVideoRenderer | Validated frame ingestion and decode scheduling | Main-thread blocking GPU waits |
| PyroWaveMetalPresenter | Texture pool, conversion, drawable and GPU completion | Host encoder selection |
| Existing Apple renderer | H.264/HEVC path and supported future codecs | PyroWave packet parsing |

The current upstream paths are described in PLAN.md. Initial layout in integration/ contains design notes only. Actual source should live at upstream-compatible paths after import.

## Ownership and execution

A DECODE_UNIT belongs to common-c until copied/transferred into an application-owned slot and completed. Preserve loss and record boundaries during this transfer. Codec parsing/upload happens on a serial worker; UI layer configuration happens on the main thread. GPU completion releases retained slots.

Keep the same command buffer for decode/conversion when appropriate; submit presentation without CPU readback. Stop/reconnect must drain or safely cancel ownership without retaining freed packet pointers.

Keep GPU jobs <=2 and pending CPU work <=1. Benchmark ingestion, GPU completion and presentation separately. Auto selects before negotiation; renderer dispatch uses the negotiated format.
