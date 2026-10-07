# Moonlight tvOS PyroWave

Scaffold for a Moonlight tvOS client with low-latency PyroWave GPU decoding and automatic codec selection that prefers PyroWave when it passes device, protocol, performance and network checks.

**Status: planning only.** There is no app target, decoder implementation, codec-selection runtime or measured Apple TV benchmark in this repository yet. This project is independent of the upstream maintainers.

## Scope

- Start from the standard Moonlight iOS/tvOS client.
- Target Apple TV 4K, including the second-generation A12 device.
- Reuse the native PyroWave Metal backend and Nonary wire protocol.
- Make PyroWave available as a manual codec and a preferred candidate in Auto mode.
- Measure decode latency separately from throughput and display latency.
- Keep H.264/HEVC available; admit AV1 only on clients with a verified backend.

The encoder runs on the host PC. The client chooses the codec/profile, negotiates it with the host, and selects its local decoder.

## Read first

| Document | Purpose |
| --- | --- |
| [Implementation plan](docs/PLAN.md) | Milestones and source integration points |
| [Decode performance](docs/decoding-performance.md) | Metrics, optimization priorities and benchmark protocol |
| [Automatic codec selection](docs/codec-selection.md) | PyroWave-first selection and fallback contract |
| [Architecture](docs/architecture.md) | Proposed component ownership |
| [Source research](docs/research.md) | Verified upstream facts and pinned references |
| [Dependency manifest](configs/upstreams.lock.json) | Reviewed source revisions; sources are not vendored |
| [Policy specification](configs/codec-policy.example.json) | Proposed settings; not loaded by an application |
| [Benchmark report template](benchmarks/templates/report.json) | Empty result template; no claimed measurements |

## Repository layout

Documentation lives in `docs/`; planned integration boundaries live in `integration/`; benchmark definitions live in `benchmarks/`; reviewed dependency and policy specifications live in `configs/`. GitHub issue/PR templates are provided. This scaffold intentionally contains no placeholder decoder code or fake Xcode project.

See [upstream import](docs/upstream-import.md) before importing Moonlight or registering submodules. Development starts only after a separate instruction authorizes implementation.

## First engineering milestone

Decode and present a saved PyroWave frame correctly on the physical A12 Apple TV, then measure sustained 1080p60 and 4K60 behavior. A simulator pass does not prove A12 compatibility.

## License

Original scaffold material uses the MIT license selected for this repository; see [LICENSE](LICENSE). Preserve each upstream license and copyright when source is imported. Moonlight sources remain GPL-3.0-or-later and PyroWave remains MIT; this scaffold's license does not replace those licenses. See [third-party policy](third_party/README.md).
