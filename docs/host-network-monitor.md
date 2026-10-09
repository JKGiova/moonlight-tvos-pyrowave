# Host dashboard and pre-stream network monitor

Implemented for the generated tvOS client. A saved PC always opens its dashboard.
The five-second monitor runs only while that dashboard is in the foreground.
Physical Apple TV layout, focus and LAN/WAN behavior still need device tests.

## Dashboard states

| Evidence | Layout and controls |
| --- | --- |
| Matching, paired HTTPS streaming service | Existing apps grid and launch/resume/quit controls; bottom metrics panel and Test bandwidth. Bottom scroll space keeps focused apps clear of the panel. |
| PC responds but service is unavailable | Horizontally and vertically centered panel, response metrics, Retry and Wake PC when a MAC address is saved. |
| No service or echo replies across repeated checks | Centered “PC unreachable” panel, Retry and Wake PC when configured. The message allows power-off, disconnection and blocked probes. |
| Service found but pairing is missing/invalid | Centered Pair PC panel. Only explicit selection enters the existing PIN workflow. |
| Initial check or network-path change | Centered checking state. Old asynchronous results cannot authorize apps or bandwidth. |

The view automatically returns to apps after a successful service check.
Refreshing metrics does not reload the grid or move focus each tick. App lists
refresh at most every 15 seconds after successful retrieval; serverinfo updates
current-game state every five seconds. Long-press host management remains in the
PC picker.

## Measurements

- **Service response / HTTP response:** monotonic request-to-completion timing,
  including connection/TLS setup and service processing. It is not ICMP RTT.
- **Ping RTT:** optional echo fallback after service failure. Darwin unprivileged
  datagram ICMP sockets support IPv4/IPv6; DNS and socket reads are asynchronous
  and cancellable. Replies must match the address, type/code, identifier,
  sequence and random 128-bit token, plus the ICMPv4 checksum. Denied sockets or
  missing replies remain unknown, never measured zero.
- **Connection response:** HTTP errors or explicit connection refusals show an
  endpoint response without proving service availability. Firewalls affect this.
- **Variation:** population standard deviation of at most 12 successful samples
  from the same timing source. Failed probes never become latency samples.
- **Download:** slowest of three complete authenticated HTTPS transfers after
  one discarded warm-up. The raw rate includes setup; UI labels method, age and
  staleness. This is not link speed or guaranteed UDP capacity.

Response timing becomes stale after 15 seconds and download evidence after 30
seconds. Reopening the dashboard starts a new observation. Network-path or
selected-address changes invalidate samples. Nothing is stored as Auto
qualification; the existing PyroWave Auto gates are unchanged.

## Bandwidth protocol and limits

The pinned Vibeshine source advertises `PyroWaveBandwidthProbeBytes=33554432`
through the paired service. The client requires that exact size and a matching
host identity over certificate-pinned HTTPS before requesting
`/pyrowave-bandwidth-probe`. It reuses Moonlight authentication and rejects
redirects. The endpoint is not inferred for other hosts.

One 32 MiB warm-up and three 32 MiB transfers are sequential: maximum **128 MiB
and eight seconds**, with at most two seconds per request. Chunks are counted and
discarded, never accumulated or written to disk. Partial, oversized, failed or
timed-out transfers cannot create a new bandwidth result.

An automatic test runs once per dashboard visit when the service supports it and
no app is active. Otherwise use Test bandwidth. A per-host, in-process 60-second
cooldown also covers leaving/reopening the dashboard. HTTP 429 ends the test
without automatic retry. The host's eight-requests-per-minute quota remains
authoritative, including after app restarts. Failed retests retain the previous
result's original timestamp. The displayed raw rate has no Auto headroom applied.

Lightweight responses are capped at 64 KiB and two seconds. App-list loads have a
separate 2 MiB cap. Only one request/probe sequence is active; slow work skips a
tick instead of queuing another. Optional echo has a 1.5-second deadline including
DNS. Each refresh checks the unique saved endpoint candidates until the matching
service is found. Refused connections, a different host identity, pairing errors
and an echo reply do not prevent trying the remaining addresses. If none provides
the service, retain the strongest reachability evidence from that refresh; a later
timeout must not overwrite an earlier response with an offline result. A full
cycle can exceed five seconds on unresponsive routes; timer ticks still refresh
sample ages without starting overlapping requests.

## Cancellation

Back to PCs, background, pairing and controller exit stop the monitor.
Launch/resume cancels the timer, path observer, HTTP transfers, DNS and ICMP;
it waits for URLSession invalidation and socket closure, then drains existing
discovery workers before creating the stream. A controller-owned cancellation
barrier retains pending stops across Back/re-entry and host changes, including
when there is no current monitor. Background/disappearance invalidates a pending
launch immediately, allowing a subsequent foreground visit to restart monitoring.
Dashboard identity/generation
rejects late callbacks. No monitor or bandwidth probe runs during streaming.
Passive stream telemetry is outside this update.

## Implementation and checks

- `native/apple/MLHostNetworkMonitor.*`: cadence, identity/admission, states and capacity adapter.
- `native/apple/MLHostProbeSession.*`: bounded URL loading, authentication delegation and cancellation.
- `native/apple/MLHostPing.*`: optional bounded DNS/ICMP fallback.
- `native/apple/MLHostMonitorBarrier.*`: waits for current and historical monitor stops.
- `native/apple/MLHostDashboardView.*`: footer and centered panel.
- `native/client/host_monitor_policy.hpp`: freshness, statistics, calibration and ICMP validation.
- `integration/patches/moonlight-host-dashboard.patch`: selective tvOS integration. Pristine upstream pins are unchanged.

Portable sanitizer tests cover freshness, statistics, calibration and malformed
ICMP parsing, including 10,000 randomized packets. Mac fixtures execute the real
URL loader and monitor for normal/service/pairing/unreachable states, recovery,
wrong identities, alternate-address recovery, response limits, hard deadlines,
partial transfer, quota, HTTP 429 and app-list authentication revocation. Tests
also cover historical/reentrant cancellation barriers and absence of timer probes
after stop. Native network checks run under AddressSanitizer/UndefinedBehaviorSanitizer.
They substitute upstream models/parsers/authentication and ping results;
they do not validate TLS pairing or physical network speed. Separate Mac loopback
tests execute the actual IPv4/IPv6/DNS ping helper, DNS deadline and repeated
cancellation. Apple targets use the SDK's default system-library linkage for DNS
services; no standalone `libdns_sd.tbd` dependency is added. CI also compiles the integrated
Debug/Release device and Debug simulator targets and runs Xcode static analysis.

## Physical acceptance checklist

1. Generate a fresh client, preserving old signing edits:
   `python3 tools/prepare_client.py --client-dir build/client/Moonlight-dashboard`.
   Open its Xcode project, select Moonlight TV, and reuse your Team and bundle ID.
2. With paired Vibeshine open, check app controls, bottom metrics, scrolling and
   remote focus at 1080p/4K. Include empty and large app lists.
3. Close Vibeshine while allowing ping, then reopen it: centered service panel
   must recover to apps. Block ping too: repeated failures must show the cautious
   unreachable message. Test Wake PC with and without a saved MAC.
4. Exercise pairing/re-pairing, custom ports, IPv4/IPv6, LAN/WAN changes, and an
   ordinary host without the optional bandwidth capability.
5. During a bandwidth test select Launch/Resume, Back and Home. Verify host-side
   traffic stops and no probe remains after stream creation; repeat reconnects.
6. Compare received byte counts/rates with a controlled network reference.
   Slow-route timeouts mean unavailable, not zero Mbps.

## Sources

- [Pinned Vibeshine protocol](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Vibeshine payload, quota and authentication handler](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/src/nvhttp.cpp)
- [Apple datagram ICMP reference](https://developer.apple.com/library/archive/samplecode/SimplePing/Listings/Common_SimplePing_m.html)
- [URLSession cancellation](https://developer.apple.com/documentation/foundation/urlsession/invalidateandcancel())
