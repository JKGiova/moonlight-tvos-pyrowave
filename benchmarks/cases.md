# Planned benchmark cases

| Case | Profile | Purpose |
| --- | --- | --- |
| B01 | 720p60 SDR 4:2:0 | First saved-frame decode and correctness |
| B02 | 1080p60 SDR 4:2:0 | Initial Auto admission and comparison |
| B03 | 4K60 SDR 4:2:0 | Target-device performance and thermal qualification |
| B04 | Dimensions not aligned to 32 | Layout, padding and edges |
| B05 | Truncated/corrupted data | Parser and lifetime robustness |
| B06 | UDP loss/reorder/bursts | Partial decode and network admission |
| B07 | Reconnect/drawable loss | Pool and stop lifecycle |
| B08 | HDR / 4:4:4, later | Exact-profile qualification |
| B09 | Same saved frames on A15 | Native/portable backend numerical equivalence, where both can run |
| B10 | Model/backend/OS changes | Cache invalidation, no admission inherited across devices |
| B11 | Host monitor, idle and streaming | Five-second cadence, multi-host scheduling, freshness, route changes, unsupported probes and monitor on/off overhead |

Each valid profile uses flat, gradient, text, detail stress and representative captured content. See ../docs/decoding-performance.md for methodology and acceptance gates.

Run applicable cases on A2169, A2737 and A2843. B01/B02/B03 begin with SDR 8-bit 4:2:0; B03 passing is required before claiming 4K60 PyroWave for that model. B06 uses Wi-Fi on all models and Ethernet additionally on A2169/A2843. Each admitted profile requires its own sustained/thermal run; failures remain explicit and use a verified fallback. See [device-support.md](../docs/device-support.md).
