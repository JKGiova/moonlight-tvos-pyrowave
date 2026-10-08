# Apple TV device support plan

Status: scope checked on 2026-10-07; development update 2026-10-08. The user reports standard-client streaming working on their A12/tvOS 27 Apple TV. This is an unmeasured smoke test, not model/profile qualification. PyroWave is untested on every physical model.

## Scope policy

Target every Apple TV compatible with the latest **stable** tvOS, excluding beta-only compatibility. Apple currently lists tvOS 27, released 2026-09-14, and the second and third Apple TV 4K generations. Include both third-generation variants. This is a hardware coverage policy, not an automatically raised minimum deployment target: decide the app's minimum OS and compatible toolchain during D0.

| Model | Model number | SoC / expected Metal family | Planned PyroWave path | Network validation | Qualification |
| --- | --- | --- | --- | --- | --- |
| Apple TV 4K, 2nd generation | A2169 | A12 / Apple5 | Experimental portable dequantizer implemented | Wi-Fi and Ethernet | Not tested |
| Apple TV 4K, 3rd generation, Wi-Fi | A2737 | A15 / Apple8 | Native Apple7-or-later candidate | Wi-Fi | Not tested |
| Apple TV 4K, 3rd generation, Wi-Fi + Ethernet | A2843 | A15 / Apple8 | Native Apple7-or-later candidate | Wi-Fi and Ethernet | Not tested |

Apple TV HD A1625 and Apple TV 4K first generation A1842 are outside this initial scope because they are not compatible with tvOS 27. No inference about their ability to decode PyroWave is made here. If broader legacy support is requested, add it as a separate scope decision and qualification matrix.

## One app, feature-selected backends

Use one tvOS app target. The expected GPU family above is planning information: query actual device capabilities and verify shader/pipeline creation, threadgroup limits, memory and profile support before choosing a backend. The pinned native PyroWave device gate requires Apple7; A15/Apple8 is therefore a candidate, while A12/Apple5 now has an experimental portable path. This is an inference from GPU families and the reviewed upstream gate, not proof of successful decoding.

The implementation preserves the native path for newer GPUs and selects the experimental portable path for A12. See [Apple5 details](apple5-decoder.md). On A15, compare native and portable numerical output where both can execute. Select only a correct backend, then use physical-device latency and throughput evidence to qualify it. Never force all chips onto the portable path merely to share a build.

## Qualification and release coverage

- Establish standard Moonlight H.264/HEVC startup, streaming, input/audio and reconnect on every in-scope model.
- Bring up saved-frame PyroWave correctness on physical A12 and A15; complete correctness, latency, queue, memory and thermal checks on every listed model.
- Qualify 1080p60 SDR and 4K60 SDR separately. HDR, bit depth and chroma extensions require exact-profile evidence; no silent downgrade to gain eligibility.
- Keep qualification/cache keys separate by model identifier, selected backend, app/shader revision, OS version/build and profile. The two A15 variants do not inherit each other's Auto result.
- Test Wi-Fi on all models and Ethernet where present. Network admission belongs to the actual route and is refreshed separately from decode measurements.
- Prefer PyroWave in Auto only after all device/profile/performance/host/network gates pass. Otherwise use a verified hardware fallback and show the rejection reason. No benchmark means no admission.
- Release claims name exactly the models and profiles qualified. A model can run the app with a supported hardware codec even while PyroWave remains explicitly unqualified.

The planned initial latency gates are shared across devices; measured values and admissible profiles are device-specific. See [decode performance](decoding-performance.md), [codec selection](codec-selection.md) and [benchmark cases](../benchmarks/cases.md). The [device manifest](../configs/devices.json) records reviewed scope only and must not serve as runtime qualification.

## Maintenance

Review Apple sources at each stable tvOS major release and Apple TV hardware launch, updating the date and manifest. Newly compatible models enter the planned matrix with untested status and need feature probes and physical qualification. Changes to the latest-stable cohort do not automatically remove support already released or change deployment settings; record those decisions explicitly. OS/build and shader changes invalidate affected benchmark evidence before Auto reuse.

## Primary sources

- [Apple security releases: stable tvOS version and release date](https://support.apple.com/it-it/100100)
- [Apple tvOS 27 guide: supported second and third generations](https://support.apple.com/it-it/guide/tv/atvbac878c90/27/tvos/27)
- [Apple TV model identification and variant numbers](https://support.apple.com/en-gb/101605)
- [Apple TV 4K second-generation specs: A12](https://support.apple.com/it-it/111922)
- [Apple TV 4K third-generation specs: A15 and network variants](https://support.apple.com/it-it/111839)
- [Apple Metal feature-set tables: GPU families and feature requirements](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
- [Metal Apple5 family: A12](https://developer.apple.com/documentation/metal/mtlgpufamily/apple5)
- [Metal Apple8 family: A15](https://developer.apple.com/documentation/metal/mtlgpufamily/apple8)
- [Pinned PyroWave research and upstream references](research.md)
