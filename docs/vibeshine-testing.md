# Repeatable testing with the Vibeshine PC

Status: proposed development workflow only. No test runner, client launch hook, pairing automation or device access is implemented. The user-selected PC runs Vibeshine and becomes the primary real streaming host.

## Roles and prerequisites

| Machine | Role |
| --- | --- |
| User's PC with Vibeshine | Capture/encode known test content, serve the stream, collect host timings |
| Mac with Xcode and signing | Build the tvOS client and install/launch it on a configured physical Apple TV |
| Physical Apple TV | Receive, decode and present the stream; collect client/network timings |
| Local test runner | Coordinate an explicit run using reachable host, Mac and Apple TV, then collect sanitized results |

Editing sources and coordinating work can happen on the same PC that runs Vibeshine. The tvOS client and its GPU timing still run on the Apple TV; a Windows client connected to localhost is a protocol smoke test, not an Apple TV latency result. The cloud GitHub workspace has no automatic access to the user's LAN. Runner connectivity, signing, device trust/developer setup and host identity are established locally when implementation starts.

Pin host software during comparisons. Reviewed reference: Vibeshine 2.0.0 tag at `0689b2e021d6106612a7ed72a34dacc714b7a133`, documenting PyroWave bitstream `186f0393`. Record the version/binary actually installed, GPU and capture method before declaring compatibility; installing Vibeshine does not prove its encoder can run PyroWave on the current capture adapter. New host versions need capability and protocol checks.

## Initial setup and automatic connection

1. Build/install the standard client baseline with a persistent development bundle identity and signing configuration. Complete normal PIN pairing with the intended PC once; keep pairing material in the client keystore.
2. Select the intended host identity and a dedicated test application/app ID through discovery/app list. Store endpoint and selection in ignored local configuration, using [the profile template](../configs/test-host.example.json). No addresses, private keys or PINs in the public repository.
3. A development run explicitly enables its auto-connect launch hook. Once the Apple TV app starts, it selects this paired host, verifies capability/bitstream, negotiates the requested codec/profile and launches the chosen test app. It must not silently choose a different host or app.
4. Use a 30-second startup timeout and initially one attempt per run. Unpaired, unreachable, busy/occupied host, protocol mismatch and missing device access produce separate outcomes, not a retry loop. Do not cancel or take over an unrelated session. Reinstallations that erase pairing require the normal pairing flow again.
5. The regular product keeps its normal host selection and launch behavior. Debug auto-connect is a per-run setting, not a permanent default or a pairing bypass.

These are planned hooks and orchestration responsibilities; no specific Xcode device-control command or host admin API is assumed without source/toolchain verification.

## Development loop

Edit sources, build/sign on the Mac, install/launch on the target Apple TV, auto-connect to the paired Vibeshine PC, run fixed content, collect timestamps and stop only the test session. On the next build, reuse pairing and repeat. Local runner scripts can coordinate these steps later after device/source integration; a GitHub-only job cannot substitute for a physical LAN-connected device runner.

Start live testing as soon as the standard baseline works (D0), alongside saved-frame GPU tests (D1/D2). Add manual PyroWave after protocol/renderer bring-up, then test Auto and rejection/fallback scenarios. Saved-frame tests isolate the decoder; live tests exercise host encoding, transport and presentation together.

## Measurement controls

- Compare H.264, HEVC and PyroWave using the same content, requested profile and fixed-quality methodology. Record actual negotiated codec and any fallback; a run requesting PyroWave that used HEVC is not a PyroWave result.
- Separate host capture/encode timing, network RTT/goodput/loss, client parsing/upload/GPU decode and presentation. Unknown timings remain null with their measurement boundary.
- Record concurrent host work. Editing is fine for smoke tests, but compile jobs, GPU workloads and capture of a changing development desktop can contaminate performance measurements. Qualification uses repeatable content and controlled host load.
- Monitor RTT/goodput every five seconds. Calibrate bandwidth before the session using the supported probe; do not run the 32 MiB endpoint every monitoring tick.
- Alternate/randomize codec order, record warm-up separately, collect 10,000 steady-state frames and run a 30-minute soak for each admitted model/profile. An A12 run does not qualify A15 or another model.
- Keep raw captures/configuration/logs under ignored benchmarks/local/. Commit only reviewed, sanitized summaries using [the report template](../benchmarks/templates/report.json).

## Existing Vibeshine bandwidth probe

The pinned paired HTTPS service exposes `/serverinfo` metadata and GET `/pyrowave-bandwidth-probe` returning 32 MiB. The server enforces eight requests per client/minute. Warm-up plus three measurements uses four requests / 128 MiB; take the slowest completed payload-transfer rate and apply the 20% headroom once in the client policy. Respect the planned total eight-second and per-request two-second limits, cancellation and rate limits. Unsupported/failed/incomplete probes do not invent a capacity number. Source method, byte/time caps and separate TLS setup are reported.

This gives a bulk host-to-client estimate, not an upload estimate or guarantee of loss-free UDP. The same-route live stream still needs network qualification. See [host monitoring](host-network-monitor.md) and [codec selection](codec-selection.md).

## Primary references

- [Vibeshine 2.0.0 release](https://github.com/Nonary/vibeshine/releases/tag/2.0.0)
- [Pinned protocol and bandwidth guide](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Pinned host probe implementation](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/nvhttp.cpp)
- [Source manifest](../configs/upstreams.lock.json), [device matrix](device-support.md), [benchmark cases](../benchmarks/cases.md)
