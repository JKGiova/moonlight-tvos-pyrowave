# Moonlight tvOS PyroWave

Development workspace for a Moonlight tvOS client with low-latency PyroWave GPU decoding and automatic codec selection that prefers PyroWave when it passes device, protocol, performance and network checks.

**Status: experimental client integration started.** The genuine Moonlight app and native PyroWave sources are pinned submodules. Implemented: Nonary framing validation, portable codec tests, video encoding/round-trip harness, selective protocol patches and a bounded asynchronous Metal decoder/presenter connected to the tvOS client. The live path requires an explicit experimental request and 8-bit SDR 4:2:0; the integrated unsigned ARM64 tvOS build and actual presenter shader/pipeline compilation passed in CI. The user reports standard-client streaming working on A12/tvOS 27; PyroWave remains untested on physical Apple TVs. The Apple5 dequantizer, capability-selected decoder-only factory and persistent experimental codec choice are now implemented. Normal qualified Auto, host monitoring and partial-frame recovery remain pending. No Apple TV device benchmark is claimed. This project is independent of the upstream maintainers.

## Scope

- Start from the standard Moonlight iOS/tvOS client.
- Target every Apple TV compatible with the latest stable tvOS: currently tvOS 27, Apple TV 4K second generation and both third-generation variants. See the [device support matrix](docs/device-support.md), checked on 2026-10-07.
- Plan one tvOS app with capability-selected Metal paths for A12 and A15; qualify each model/profile independently.
- Reuse the native PyroWave Metal backend and Nonary wire protocol.
- Make PyroWave available as a manual codec and a preferred candidate in Auto mode.
- Measure decode latency separately from throughput and display latency.
- Refresh host RTT and network telemetry every 5 seconds, showing measured throughput separately from estimated available bandwidth and stale/unknown values.
- Use the user-selected PC running Vibeshine as the primary live test host, with opt-in debug reconnection after initial pairing.
- Keep H.264/HEVC available; admit AV1 only on clients with a verified backend.

The encoder runs on the host PC. The client chooses the codec/profile, negotiates it with the host, and selects its local decoder.

## Read first

| Document | Purpose |
| --- | --- |
| [Device support matrix](docs/device-support.md) | All in-scope models, GPU paths and release qualification |
| [Device manifest](configs/devices.json) | Reviewed hardware scope; not a runtime allowlist |
| [Apple5 decoder](docs/apple5-decoder.md) | Portable shader, candidate selection and correctness checks |
| [Development status](docs/development-status.md) | Implemented code, actual checks and remaining work |
| [Reliability and Xcode review](docs/reliability-and-xcode.md) | Regression coverage, compiler warnings and prioritized fixes |
| [Build and encoding tests](docs/build-and-test.md) | Initialize sources, build genuine targets, encode the chosen video |
| [Implementation plan](docs/PLAN.md) | Milestones and source integration points |
| [Decode performance](docs/decoding-performance.md) | Metrics, optimization priorities and benchmark protocol |
| [Automatic codec selection](docs/codec-selection.md) | PyroWave-first selection and fallback contract |
| [Vibeshine test workflow](docs/vibeshine-testing.md) | Reconnect the physical Apple TV to the same PC for repeatable tests |
| [Host network monitor](docs/host-network-monitor.md) | Five-second refresh, RTT, bandwidth estimation and Auto input |
| [Network specification](configs/network-monitor.example.json) | Probe cadence, budgets and freshness policy; not runtime settings |
| [Architecture](docs/architecture.md) | Proposed component ownership |
| [Source research](docs/research.md) | Verified upstream facts and pinned references |
| [Dependency manifest](configs/upstreams.lock.json) | Reviewed source revisions and registered dependency pins |
| [Policy specification](configs/codec-policy.example.json) | Proposed settings; not loaded by an application |
| [Benchmark report template](benchmarks/templates/report.json) | Empty result template; no claimed measurements |

## Repository layout

The genuine app lives in the `app/Moonlight` submodule with its original Xcode project. `third_party/pyrowave` contains the pinned native Metal dependency. Selective app/common-c patches live in `integration/patches`; `tools/prepare_client.py` creates a generated client checkout under `build/client/` without changing the pristine submodules. The Metal renderer and queue/color/identity helpers live in `native/apple` and `native/client`. Implemented protocol validation lives in `native/protocol`; runnable tests and build/encoding tools live in `tests/` and `tools/`. Design and progress live in `docs/`, benchmarks in `benchmarks/`, and reviewed settings/references in `configs/`. No fake Xcode project is generated.

Clone with `git clone --recurse-submodules https://github.com/JKGiova/moonlight-tvos-pyrowave.git`, then follow [build and test](docs/build-and-test.md). On macOS, `python3 tools/build_engine.py` builds the real Metal harness and `python3 tools/encode_test_video.py --backend metal --roundtrip` generates and encodes the video, validates its frames, and decodes it for comparison. `python3 tools/build_tvos.py --sdk appletvos` builds the integrated experimental client; add `--baseline` for the pristine app. Read [experimental client testing](docs/experimental-client.md) before requesting PyroWave.

## First engineering milestone

Decode and present saved PyroWave frames correctly on physical A12 and A15 Apple TVs, using the portable Apple5 path and the native Apple7-or-later candidate respectively. Then measure sustained 1080p60 and 4K60 behavior and complete release qualification on every model in the matrix. A simulator pass or an A15 pass does not qualify A12; neither third-generation variant automatically qualifies the other.

## License

Original scaffold material uses the MIT license selected for this repository; see [LICENSE](LICENSE). Preserve each upstream license and copyright when source is imported. Moonlight sources remain GPL-3.0-or-later and PyroWave remains MIT; this scaffold's license does not replace those licenses. See [third-party policy](third_party/README.md).
