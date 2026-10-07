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

Each valid profile uses flat, gradient, text, detail stress and representative captured content. See ../docs/decoding-performance.md for methodology and acceptance gates.
