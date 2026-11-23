# Testing with Vibeshine

The PC runs Vibeshine, the Mac builds/signs the client, and the physical Apple TV
receives, decodes and presents the stream. GitHub Actions runs software checks on
hosted runners; it does not connect to the owner's paired PC or Apple TV.

## Existing manual workflow

1. Record the installed host version and capture/encoder settings. The repository's
   protocol reference is Vibeshine 2.0.0 at
   `0689b2e021d6106612a7ed72a34dacc714b7a133`, using bitstream `186f0393`;
   this does not identify the version installed on a particular PC.
2. Follow the [Apple TV installation guide](experimental-client.md#install-on-a-physical-apple-tv).
   Select the PC, pair through the PIN flow and choose the application manually.
3. Start a new stream after changing codec/profile/bitrate settings. Verify the
   negotiated codec and backend in the overlay.
4. Record the scene, build, device/OS, network route, requested and applied bitrate,
   displayed timings and counter changes over a known interval. Keep raw local
   logs/captures in ignored `benchmarks/local/`.

The existing local profile example is reference data, not a loaded auto-connect
configuration. There is no automatic host selection or Debug auto-connect feature.

## Interpreting results

- Hold content, host workload, build and network constant for comparisons. The
  recorded 150 Mbps and 300 Mbps observations used different builds and do not
  establish a causal bitrate/drop relationship.
- Keep network loss separate from client queue replacements. Record beginning/end
  counters and interval length rather than treating a cumulative count as a rate.
- Keep host processing, network RTT, combined GPU execution, client Ready and
  visible display latency separate. [Timing definitions](decoding-performance.md)
- The host's actual bitrate can differ from the client request. The source-reviewed
  host log messages `Client configured bitrate is ... Kbps` and
  `Final adjusted video encoding bitrate is ... Kbps` distinguish the received
  budget from its encoding adjustment. Those logs have not been collected for the
  owner's 120 Mbps/300 Mbps observations.
- No matched HEVC/PyroWave latency comparison or on-screen latency measurement is
  recorded. A successful standard-codec session does not prove PyroWave decoding.

## Retained bandwidth-probe implementation

The optional reference dashboard can query an advertised authenticated HTTPS
`/pyrowave-bandwidth-probe` endpoint with 32 MiB responses and a host quota of
eight requests per client per minute. Its implementation performs one warm-up
and three transfers with bounded time/bytes and cancellation. The standard
prepared app does not apply the dashboard patch or expose that probe UI.
[Reference monitor details](host-network-monitor.md)

## References

- [Vibeshine release](https://github.com/Nonary/vibeshine/releases/tag/2.0.0)
- [Pinned protocol](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Pinned RTSP bitrate handling](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/rtsp.cpp)
- [Pinned probe handler](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/nvhttp.cpp)
