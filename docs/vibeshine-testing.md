# Repeatable testing with the Vibeshine PC

Use the PC as the Vibeshine host, the Mac to build and sign, and the physical Apple TV to receive, decode and present the stream. GitHub Actions runs software checks on hosted runners. Live streaming and timing measurements happen locally.

## Setup and test

1. Review the installed Vibeshine version, capture adapter and PyroWave capability. The project’s protocol reference is Vibeshine 2.0.0 at `0689b2e021d6106612a7ed72a34dacc714b7a133`, using bitstream identity `186f0393`.
2. Follow the [Apple TV install guide](experimental-client.md#install-on-a-physical-apple-tv). Select the PC in Moonlight Pyro, use standard PIN pairing, then select the intended desktop or application from the app list. Automatic host selection and Debug auto-connect are planned.
3. Start a new stream for each setting. Verify the negotiated codec in the overlay, then record the resolution, FPS, bitrate setting, applied bitrate if available, RTT, network loss and queue counter changes over a fixed duration.
4. For an A12 bitrate comparison, hold the scene, host settings, build and network constant. Start at 150 Mbps and repeat at 200 Mbps. Keep captures and logs under ignored `benchmarks/local/` and remove host addresses, PINs and pairing material from anything you publish.

## Measurement controls

- Compare H.264, HEVC and PyroWave using the same content, requested profile and fixed-quality methodology. Record actual negotiated codec and any fallback; a run requesting PyroWave that used HEVC is not a PyroWave result.
- Separate host capture/encode timing, network RTT/goodput/loss, client parsing/upload/GPU decode and presentation. Unknown timings remain null with their measurement boundary.
- Record concurrent host work. Editing is fine for smoke tests, but compile jobs, GPU workloads and capture of a changing development desktop can contaminate performance measurements. Qualification uses repeatable content and controlled host load.
- Record RTT and reported network loss during the session. Use a separate controlled measurement when you need network goodput or capacity.
- Alternate/randomize codec order, record warm-up separately, collect 10,000 steady-state frames and run a 30-minute soak for each admitted model/profile. An A12 run does not qualify A15 or another model.
- Keep raw captures/configuration/logs under ignored benchmarks/local/. Commit only reviewed, sanitized summaries using [the report template](../benchmarks/templates/report.json).

## Reference Vibeshine bandwidth probe

This probe is reference material for the optional dashboard patch. The default build uses the standard app list. The pinned paired HTTPS service exposes `/serverinfo` metadata and GET `/pyrowave-bandwidth-probe` returning 32 MiB. The server enforces eight requests per client/minute. Warm-up plus three measurements uses four requests / 128 MiB; take the slowest completed payload-transfer rate and apply the 20% headroom once in the client policy. Respect the planned total eight-second and per-request two-second limits, cancellation and rate limits. Unsupported/failed/incomplete probes do not invent a capacity number. Source method, byte/time caps and separate TLS setup are reported.

This gives a bulk host-to-client estimate, not an upload estimate or guarantee of loss-free UDP. The same-route live stream still needs network qualification. See [host monitoring](host-network-monitor.md) and [codec selection](codec-selection.md).

## Primary references

- [Vibeshine 2.0.0 release](https://github.com/Nonary/vibeshine/releases/tag/2.0.0)
- [Pinned protocol and bandwidth guide](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Pinned host probe implementation](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/nvhttp.cpp)
- [Source manifest](../configs/upstreams.lock.json), [device matrix](device-support.md), [benchmark cases](../benchmarks/cases.md)
