# Moonlight tvOS PyroWave

Moonlight Pyro is an experimental Moonlight client for tvOS with PyroWave decoding on the Apple TV’s GPU. Vibeshine encodes the stream on the host PC. The app uses the standard Moonlight host and app selection screens, with a persistent **PyroWave (SDR)** codec setting and an optional in-stream statistics overlay.

The project owner reported 30 minutes of 4K60 PyroWave on an A12 Apple TV at **150 Mbps** with **zero queue drops**. A separate 300 Mbps run on the newer build showed **1,299 queue drops** in a screenshot. Session duration for that screenshot is unknown. These are device observations. Formal performance qualification and automatic PyroWave codec admission are still pending. [Device observations](docs/development-status.md#apple-tv-device-observations)

## Quick start

You’ll need a Mac with Python 3.10+ and Xcode with the tvOS SDK, an Apple TV paired with Xcode, and a PC running a PyroWave-capable Vibeshine build. Put the Apple TV and PC on a reachable network.

1. Clone the repo, verify the pinned dependencies, and generate the Xcode project.

   ```sh
   git clone --recurse-submodules https://github.com/JKGiova/moonlight-tvos-pyrowave.git
   cd moonlight-tvos-pyrowave
   python3 tools/bootstrap.py
   python3 tools/prepare_client.py --client-dir build/client/Moonlight-local
   open build/client/Moonlight-local/Moonlight.xcodeproj
   ```

   After updating an existing clone, use a new path under `build/client/` if the integration inputs changed. Generated projects can contain local signing edits.

2. In Xcode, select **Moonlight TV**. Under **Signing & Capabilities**, enable automatic signing, select your team and use a unique bundle identifier. Reuse your existing identifier and team when updating a local installation. Choose the paired Apple TV and press **⌘R**.
3. Open **Moonlight Pyro** on the TV. Pair with the Vibeshine PC using the PIN flow if needed. Start a stream with the standard codec settings to check connectivity.
4. In the app’s tvOS Settings entry, choose **Preferred Codec → PyroWave (SDR)**, turn off HDR, and turn on **Statistics Overlay**. Start at **720p60**. The overlay should show PyroWave and its backend, such as `metal-portable-apple5` on A12.
5. Once that works, move to 1080p60 and 4K60. For a first comparison on A12, use **150 Mbps** manually as the 4K60 baseline and see whether **Queue drops** rises over a fixed interval.

Manual bitrate requests go up to **1,000 Mbps**. **Auto (by stream profile)** in the Bitrate menu picks an initial request from the negotiated codec, resolution and frame rate. At 4K60 it requests 500 Mbps for PyroWave. The host controls the applied bitrate. **Auto** in the Preferred Codec menu still uses the standard Moonlight codec selection. [Full Apple TV guide](docs/experimental-client.md)

## Target devices and roadmap

The project targets the second-generation Apple TV 4K (A12) and both third-generation variants (A15). A12 uses the portable Apple5 decoder, and A15 is a candidate for the native Apple7-or-later backend. Each model and stream profile needs separate qualification. [Device support matrix](docs/device-support.md)

The main milestones are controlled device measurements, partial-frame recovery and automatic PyroWave codec admission. [Implementation plan](docs/PLAN.md)

## Read first

| Document | Purpose |
| --- | --- |
| [Device support matrix](docs/device-support.md) | All in-scope models, GPU paths and release qualification |
| [Device manifest](configs/devices.json) | Reviewed hardware scope; not a runtime allowlist |
| [Apple5 decoder](docs/apple5-decoder.md) | Portable shader, candidate selection and correctness checks |
| [Development status](docs/development-status.md) | Implemented code, actual checks and remaining work |
| [Reliability and Xcode review](docs/reliability-and-xcode.md) | Regression coverage, compiler warnings and prioritized fixes |
| [Apple TV installation and streaming](docs/experimental-client.md) | Signing, settings, bitrate profiles and overlay reference |
| [Build and encoding tests](docs/build-and-test.md) | Initialize sources, build genuine targets, encode the chosen video |
| [Implementation plan](docs/PLAN.md) | Milestones and source integration points |
| [Decode performance](docs/decoding-performance.md) | Metrics, optimization priorities and benchmark protocol |
| [Automatic codec selection](docs/codec-selection.md) | Planned automatic codec admission and fallback |
| [Vibeshine test workflow](docs/vibeshine-testing.md) | Repeatable comparisons on a paired Vibeshine PC |
| [Host network monitor](docs/host-network-monitor.md) | Reference dashboard patch and bandwidth probe design |
| [Network specification](configs/network-monitor.example.json) | Probe cadence, budgets and freshness policy; not runtime settings |
| [Architecture](docs/architecture.md) | Proposed component ownership |
| [Source research](docs/research.md) | Verified upstream facts and pinned references |
| [Dependency manifest](configs/upstreams.lock.json) | Reviewed source revisions and registered dependency pins |
| [Policy specification](configs/codec-policy.example.json) | Proposed settings; not loaded by an application |
| [Benchmark report template](benchmarks/templates/report.json) | Empty result template; no claimed measurements |

## Repository layout

The genuine app lives in the `app/Moonlight` submodule with its original Xcode project. `third_party/pyrowave` contains the pinned native Metal dependency. Selective app/common-c patches live in `integration/patches`; `tools/prepare_client.py` creates a generated client checkout under `build/client/` without changing the pristine submodules. The Metal renderer and queue/color/identity helpers live in `native/apple` and `native/client`. Implemented protocol validation lives in `native/protocol`; runnable tests and build/encoding tools live in `tests/` and `tools/`. Design and progress live in `docs/`, benchmarks in `benchmarks/`, and reviewed settings/references in `configs/`.

## Development checks

Use `python3 tools/run_portable_tests.py --sanitize` for parser, interoperability and runtime policy checks. On macOS, `python3 tools/build_tvos.py --sdk appletvos --client-dir build/client/Moonlight-check` compiles the integrated target without signing. [Build and test guide](docs/build-and-test.md)

The five post-merge CI jobs passed for `f57c5ab`, including Debug and Release on the device target, the Debug simulator, portable tests, Metal checks and static analysis. [GitHub Actions run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/44893326699)

## License

Original scaffold material uses the MIT license selected for this repository; see [LICENSE](LICENSE). Preserve each upstream license and copyright when source is imported. Moonlight sources remain GPL-3.0-or-later and PyroWave remains MIT; this scaffold's license does not replace those licenses. See [third-party policy](third_party/README.md).
