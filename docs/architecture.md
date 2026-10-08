# Proposed architecture

Status: runtime architecture remains under development. Native framing validation, the offline GPU harness and an experimental complete-frame streaming path are implemented. The Apple5 shader and decoder capability selection are implemented experimentally. Qualified Auto, monitoring and partial-frame recovery are pending.

| Component | Owns | Does not own |
| --- | --- | --- |
| CodecSelectionPolicy | Candidate eligibility, PyroWave preference, fallback decision | GPU decode or host encoding |
| DecoderCapabilityProbe | Device/pipeline/profile qualification | Optimistic model-name support claims |
| DecoderBenchmarkStore | Versioned physical-device measurements and invalidation | Synthetic results |
| HostNetworkMonitor | Foreground five-second scheduling, RTT sources, goodput and bounded supported probes | Saturating the stream or assuming RTT reveals bandwidth |
| HostNetworkSampleStore | Host/route/direction samples, timestamps, method, confidence and freshness | Reusing stale measurements as fresh evidence |
| common-c protocol integration | RTSP/SDP, transport, reassembly and loss metadata | UI preference or renderer internals |
| PyroWaveVideoRenderer | Validated frame ingestion and decode scheduling | Main-thread blocking GPU waits |
| Metal presenter (currently inside PyroWaveVideoRenderer) | Texture pool, conversion, drawable and GPU completion | Host encoder selection |
| Existing Apple renderer | H.264/HEVC path and supported future codecs | PyroWave packet parsing |

The current upstream paths are described in PLAN.md. integration/ contains boundary notes. The real baseline project keeps upstream-compatible paths under app/Moonlight; native/protocol implements the shared framing adapter used by both the offline harness and native/apple/PyroWaveVideoRenderer.mm. Selective integration patches are applied to a generated client under build/client by tools/prepare_client.py; pinned submodules stay pristine.

## Ownership and execution

A DECODE_UNIT belongs to common-c until copied/transferred into an application-owned slot and completed. The current complete-frame path copies opaque picture buffers; preserving lost-packet/record-start metadata requires the planned partial-frame transport patches. Codec parsing/upload happens on a serial worker; UI layer configuration happens on the main thread. GPU completion releases retained slots.

Keep the same command buffer for decode/conversion when appropriate; submit presentation without CPU readback. Stop/reconnect must drain or safely cancel ownership without retaining freed packet pointers.

Keep GPU jobs <=2 and pending CPU work <=1. Benchmark ingestion, GPU completion and presentation separately. Auto selects before negotiation; renderer dispatch uses the negotiated format.

## Hardware scope

Plan one app target for all models in [device-support.md](device-support.md). DecoderCapabilityProbe checks actual GPU families, shader compilation, pipeline limits and profile support, then selects a native Apple7-or-later or portable Apple5 candidate within the PyroWave backend. It does not infer qualification from the model manifest. DecoderBenchmarkStore keeps model/backend/OS/profile evidence separate; CodecSelectionPolicy uses that evidence before preferring PyroWave. Unknown devices retain capability-verified hardware fallback until qualified.

The [host monitor](host-network-monitor.md) runs outside decode/UI critical work and publishes immutable snapshots. It reads control RTT only within the connection lifecycle and cancels on stop/background. Auto consumes qualified route evidence before negotiation; monitoring does not switch the live codec every five seconds.
