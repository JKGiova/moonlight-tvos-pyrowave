# Moonlight Pyro for Apple TV

[![Development checks](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/workflows/ci.yml/badge.svg)](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/workflows/ci.yml)

Moonlight Pyro is an experimental game-streaming client based on
[Moonlight for iOS/tvOS](https://github.com/moonlight-stream/moonlight-ios).
It adds [PyroWave](https://github.com/Themaister/pyrowave) GPU decoding to the
Apple TV client, using native Metal. The PC running Vibeshine encodes the video;
the Apple TV receives, decodes and presents it.

- PyroWave **8-bit SDR and 10-bit HDR10, YUV 4:2:0 or 4:4:4** with explicit profile selection.
  HDR10/4:4:4 are implemented; live display/performance qualification is pending.
  HDR10+ requires a host protocol extension and is not advertised.
- Portable **Apple5** decoding on A12 and a capability-selected native
  **Apple7-or-later** decoder candidate for newer Apple GPUs.
- Standard Moonlight PC selection, PIN pairing and app list.
- Manual bitrate requests from **0.5 to 1,000 Mbps**, plus bitrate Auto by profile.
- A bounded renderer with two in-flight slots and one latest pending frame.
- In-stream backend, timing, network-loss and client-drop statistics.
- Existing Moonlight H.264/HEVC paths remain available.

PyroWave is selected explicitly. **Preferred Codec → Auto** uses the standard
Moonlight codec path; it does not automatically choose PyroWave.

## Requirements

- A Mac with Python 3.10+, Xcode and the tvOS SDK to build and sign the app.
  An Intel Mac can build the client; its shaders execute on the Apple TV.
- An Apple TV paired with Xcode. The recorded live tests use a second-generation
  Apple TV 4K with A12. A15 models have no recorded physical-device result here.
- A reachable PC running a PyroWave-capable Vibeshine build with matching bitstream
  identity `186f0393`, and a network capable of the requested stream rate.

See [device evidence](docs/device-support.md) and [host negotiation](docs/codec-selection.md).

## Installation

Build from source on the Mac:

```sh
git clone --recurse-submodules https://github.com/JKGiova/moonlight-tvos-pyrowave.git
cd moonlight-tvos-pyrowave
python3 tools/bootstrap.py
python3 tools/prepare_client.py
open build/client/Moonlight-Clean-Release/Moonlight.xcodeproj
```

Select **Moonlight TV** in Xcode. Under **Signing & Capabilities**, enable automatic
signing, select your team and enter your bundle identifier. Select the paired Apple
TV and press **⌘R**. Reuse the same team and bundle identifier when updating an
existing installation. See [installation details](docs/experimental-client.md#install-on-a-physical-apple-tv).

For an existing clone, run `git pull --ff-only` and `python3 tools/bootstrap.py`.
Run `python3 tools/prepare_client.py` after pulling changes. The same project at
`build/client/Moonlight-Clean-Release/Moonlight.xcodeproj` is updated in place.
The tool merges project changes with local signing settings and preserves Xcode
user data. Conflicting local source or project edits stop the update before any
managed file is written. Make runtime changes in `native/` or the integration
patches so GitHub and subsequent preparations include them.

## Quick start

1. Open **Moonlight Pyro** on the Apple TV.
2. Select the Vibeshine PC and complete PIN pairing if prompted.
3. Select a desktop or application from the standard Moonlight app list.
4. For PyroWave, open the app's tvOS Settings entry and choose
   **Preferred Codec → PyroWave 4:2:0**. Start with HDR off and enable **Statistics Overlay**.
   Choose **PyroWave 4:4:4** for full-resolution chroma, and enable HDR for the
   corresponding 10-bit profile. See the [HDR10 and 4:4:4 guide](docs/video-profiles.md)
   for requirements, strict profile selection and HDR10+ limitations.
5. Start a new session. The overlay identifies the actual codec and decoder;
   A12 uses `metal-portable-apple5`.

Start with 720p60 when checking a new installation. The owner's reported A12
4K60 smoke test used a manual **150 Mbps** setting. That is an observation,
not a guarantee for other scenes, builds or devices.

## Bitrate settings

The manual menu reaches **1,000 Mbps**, including 600, 700, 800 and 900 Mbps.
**Auto (by stream profile)** calculates an initial request after codec negotiation.
For PyroWave it uses a 1.6-bit-per-pixel heuristic capped at **500 Mbps**.
Bitrate Auto and codec Auto are separate settings.

The selected value is a request to the host, not a measurement of network traffic.
The host controls the applied encoding rate. See [bitrate profiles](docs/experimental-client.md#bitrate-and-comparison-runs).

## Troubleshooting

- **HEVC appears after selecting PyroWave:** check host capability, bitstream identity,
  GPU admission and profile settings. The overlay reports the negotiated codec.
  Explicit HDR/4:4:4 requests fail if unavailable; they do not silently downgrade.
- **Queue drops increase with 0% network loss:** client queue replacements and missing
  network frames are separate counters. See [statistics](docs/experimental-client.md#statistics-overlay).
- **Ready p95 is high:** it includes client waits through GPU completion, not just
  decoding. GPU time combines decode and color conversion; neither value measures
  controller-to-screen latency. See [timing definitions](docs/decoding-performance.md).
- **Preparation reports a conflict:** reconcile the named local file with the
  repository change, then rerun preparation. Local files are preserved on conflict.
  Older checkouts without a file baseline are adopted when their generated
  sources match the repository and project differences concern signing settings.
- **PyroWave startup fails:** select Auto or HEVC and start another session manually.

## Implementation and recorded results

The owner reported a **30-minute 4K60 A12 run at a 150 Mbps client setting with zero
queue drops**. Separate screenshots show client queue drops and Ready p95 around
71–74 ms. These sessions do not establish a universal bitrate ceiling or a
controlled latency comparison with HEVC. [Recorded observations and CI evidence](docs/development-status.md)

The live PyroWave integration accepts complete frames in 4:2:0/4:4:4 with 8-bit SDR
or 10-bit HDR10 presentation. The new profiles are not yet qualified for live HDR
output or sustained 4K60 operation. It has no
partial-frame recovery, automatic session retry or benchmark-aware PyroWave codec
selection. No physical A15 result is recorded. This project is independent of
upstream maintainers and does not claim release qualification.

## Practical checks

New Mac checks preserved **all 1,024 ten-bit levels** and the tested one-pixel
4:4:4 color pattern. Under 100,000 extra arrivals, the client queue kept at most
**two processing frames and one waiting**, then chose the newest frame.

Earlier physical A12 offscreen tests measured 4K processing p95 of **20.40–27.04 ms
at a synthetic 150 Mbps budget**, and **36.81–44.56 ms at 1,000 Mbps** across two
runs. These are not controller-to-screen latency, live 4K60 or HEVC comparison
results. [Plain-language test results, scope and reproduction](docs/practical-tests.md)

## Roadmap

1. Validate HDR10 and 4:4:4 with a real host and TV.
2. Measure latency, stability and a fair HEVC comparison; optimize measured bottlenecks.
3. Qualify more Apple TV models before changing codec Auto.
4. Extend the host/client protocol for genuine HDR10+ metadata.

[Detailed roadmap and completion criteria](docs/ROADMAP.md)

## Development

- [Build and test](docs/build-and-test.md)
- [Local and tvOS Simulator latency testbenches](docs/local-testbenches.md)
- [Architecture](docs/architecture.md) and [integration patches](integration/README.md)
- [Apple5 decoder](docs/apple5-decoder.md)
- [Implementation record](docs/PLAN.md)
- [Source pins and provenance](docs/upstream-import.md)
- [Reliability diagnostics](docs/reliability-and-xcode.md)

## License

Moonlight and the adapted Nonary protocol code retain GPL-3.0-or-later; PyroWave
retains MIT. Original repository material uses the MIT license in [LICENSE](LICENSE).
That license does not relicense upstream code. See [third-party attribution](third_party/README.md).
