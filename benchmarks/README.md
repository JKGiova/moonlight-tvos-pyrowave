# Recorded checks and local measurements

`results/` contains sanitized software-check records. CPU functional tests, GPU
coefficient fixtures and unsigned builds are identified separately from physical
Apple TV observations. [Owner-reported A12 observations](../docs/development-status.md#apple-tv-device-observations)
are documented without claiming formal device qualification.

- [Existing check coverage](cases.md)
- `templates/report.json`: empty report schema, not a populated device result
- `local/`: ignored raw captures, timestamps, host profiles and logs

Unavailable measurements stay null. No matched HEVC/PyroWave latency comparison,
physical A15 result or qualified automatic codec-selection record is populated.
Host addresses, pairing material and raw logs are not committed.
