# Reference dashboard and host monitor

The repository retains a dashboard implementation and
`integration/patches/moonlight-host-dashboard.patch`. **Standard client preparation
does not apply this patch**: the generated app uses the normal Moonlight app list.
The following behavior describes the retained implementation, not a feature
available in the default app. No physical dashboard UI/network validation result
is recorded.

## Implemented reference behavior

| Evidence | Reference dashboard state |
| --- | --- |
| Matching paired streaming service | Apps grid, launch/resume/quit controls and bottom metrics |
| Host response without available service | Centered service panel, Retry and Wake PC when configured |
| No service or echo replies | Cautious unreachable panel; timeouts do not prove a powered-off PC |
| Missing/invalid pairing | Explicit Pair PC action into the standard PIN workflow |
| Initial/path-change observation | Checking state; old asynchronous results are rejected |

Foreground checks use a five-second cadence for the selected host. App-list
refresh is limited to once per 15 seconds; metric updates preserve focus. Slow
requests skip a tick instead of accumulating work.

## Measurements and limits

- Service response measures request-to-completion, including setup and server work.
- Optional Darwin datagram ICMP checks address/type/code, identifier, sequence,
  token and IPv4 checksum. Missing or denied replies remain unknown.
- Variation is the population standard deviation of up to 12 successful samples
  from one source. Response evidence becomes stale after 15 seconds.
- Download uses the slowest of three complete paired HTTPS transfers after one
  warm-up. The advertised payload must be exactly 32 MiB, with matching host
  identity and pinned certificate. Redirects are rejected.
- Transfer limits are 128 MiB/eight seconds total, two seconds per request, and a
  per-host in-process 60-second cooldown. HTTP 429 ends the test without retry.
  Partial, failed or oversized transfers do not create a new result.
- Download evidence becomes stale after 30 seconds. Displayed download includes
  connection setup and is not link speed or guaranteed UDP capacity.
- Lightweight responses have a 64 KiB cap, app lists a 2 MiB cap; echo has a
  1.5-second deadline including DNS. Saved endpoint candidates are checked without
  allowing a later timeout to erase earlier reachability evidence.

An automatic bandwidth test runs once per dashboard visit only when the host
advertises support and no app is active; the reference UI also has a manual test.
This monitor does not qualify a codec or change an active stream's codec.

## Cancellation

Navigation, pairing and background stop monitoring. Launch/resume cancels timers,
path observation, HTTP transfers, DNS and ICMP, waits for invalidation/socket closure
and drains discovery work before streaming. The barrier retains historical stops
across dashboard re-entry. Generation checks reject late callbacks.

## Sources and automated coverage

| Source | Responsibility |
| --- | --- |
| `MLHostNetworkMonitor.*` | Cadence, identity, endpoint selection and state |
| `MLHostProbeSession.*` | Bounded authenticated URL loading and cancellation |
| `MLHostPing.*` | Bounded DNS/ICMP fallback |
| `MLHostMonitorBarrier.*` | Current/historical stop completion |
| `MLHostDashboardView.*` | Metrics footer and centered states |
| `host_monitor_policy.hpp` | Freshness, statistics, calibration and ICMP validation |

Sources are under `native/apple/` and `native/client/`. Portable tests exercise
policy and malformed ICMP, including 10,000 randomized packets. Mac fixtures
exercise real loader/monitor code with substituted upstream models/authentication
and ping responses: states, alternate-address recovery, deadlines, response limits,
quota and cancellation. Separate loopback tests execute IPv4/IPv6/DNS helpers.
Native tests use ASan/UBSan. These are not physical pairing/network-speed results.

## References

- [Pinned host protocol](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Probe handler](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/nvhttp.cpp)
- [URLSession cancellation](https://developer.apple.com/documentation/foundation/urlsession/invalidateandcancel())
