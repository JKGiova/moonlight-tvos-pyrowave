# Benchmark area

The offline encoder/decoder harness and generated-video script now exist. No physical Apple TV result is available. results/2026-10-07-linux-cpu-smoke.json records an actual FFmpeg CPU functional check only; it is neither PyroWave GPU performance nor Auto qualification.

- cases.md defines workloads and device/profile combinations.
- templates/report.json defines an empty sanitized report.
- local/ is ignored and reserved for raw captures/timestamps when implementation begins.

Do not replace null measurements with example numbers. Every model/profile is unqualified until physical-device evidence exists. Use the complete [device matrix](../docs/device-support.md); A12/A15 or third-generation variant results cannot be copied as qualification.

Primary live host: the user-selected PC running Vibeshine. See [test workflow](../docs/vibeshine-testing.md) and [local profile template](../configs/test-host.example.json). Local profile/host addresses and raw logs stay under benchmarks/local/.
