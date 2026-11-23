# Contributing

Read [current implementation](docs/PLAN.md), [architecture](docs/architecture.md)
and [codec behavior](docs/codec-selection.md). Build/test commands are in
[the development guide](docs/build-and-test.md).

Keep upstream pins and licenses intact; commit selective patches rather than
untracked submodule edits. Document the exact revision and physical device for
performance results. Keep measurements separate from assumptions and software
checks; unavailable timings stay null in `benchmarks/templates/report.json`.

Do not commit binaries, Xcode user/signing settings, pairing credentials, host
addresses or raw captures. The generated client lives below ignored `build/`.
