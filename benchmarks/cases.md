# Existing check coverage

| Coverage | Evidence boundary |
| --- | --- |
| Nonary framing and malformed data | Directed parser checks, random malformed frames and valid-record mutations |
| CPU codec interoperability | 12 layout/packetizer/parser profiles, including 4K geometry |
| Portable dequantization | Eight synthetic fixtures and 32,768 GPU reference coefficients in the recorded Apple5 CI run |
| Local synthetic testbenches | CPU preparation, paired validation, tiled dequant and host-lab offscreen decode/conversion; source hashes and hardware recorded |
| Complete portable decode | Two uniform synthetic profiles, 128×128 and 320×180, on an admitted runner GPU |
| Presenter | 25 offscreen color/range/orientation cases and 3,200 pixels |
| Client runtime | Queue replacement/stop ownership, exact identity and SDR color helpers |
| Source preparation and diagnostics | Python regressions for cache/pins and diagnostic collection |
| Baseline video | FFmpeg H.264/HEVC functional encoding and reconstruction, including 720p60 |
| Native build | Unsigned tvOS device Debug/Release, Debug simulator and Metal harness builds in recorded CI |
| Reference monitor | Portable policy/ICMP tests, native transport fixtures and DNS/ICMP loopback checks |
| Physical A12 | Owner-reported live sessions and overlay screenshots documented separately |

[Recorded results](../docs/development-status.md) identify revisions and limitations.
Synthetic correctness checks are not GPU video benchmarks. No HDR/4:4:4 live
client result, partial-frame recovery result or physical A15 qualification is
recorded. Historical JSON records retain their original revision context.
