# Host latency and bandwidth monitor

Status: planned feature only. Refresh host latency and network telemetry nominally every **5 seconds** while the app is active. No monitor, speed test or host endpoint is implemented in this scaffold.

## What the user sees

Each configured host has a compact network summary in the host list and a detailed view. The active session has the same measurements in its statistics panel. Display values, direction, method and age clearly:

| Value | Meaning | Five-second update |
| --- | --- | --- |
| RTT, ms | Round-trip estimate; not one-way latency or decode time | Fresh control/probe result where supported; otherwise unavailable/stale |
| Response variation, ms | Observed RTT spread across a rolling window, with sample count | Recomputed from valid samples; keep ENet-reported variance separately labelled |
| Stream receive goodput, Mbps | Unique useful host-to-client bytes received per rolling five-second interval | Recomputed during streaming; excludes duplicate/FEC/transport overhead where observable |
| Available bandwidth estimate, Mbps | Estimated useful path rate for the specified direction/method | Refresh estimate/status/age; obtain new evidence only from a supported capacity test |
| State and age | Reachable, probe failed, unsupported, unavailable or stale | Refreshed each tick; never turn unknown into 0 ms/0 Mbps |

Use host-to-client as the primary bandwidth direction because it carries video. Optional client-to-host tests have separate records; never infer symmetry. The receive rate of a 20 Mbps stream is not a claim that the path's maximum or available bandwidth is 20 Mbps. Do not estimate capacity from RTT or nominal Wi-Fi/Ethernet link speed. RTT/2 is not a measured one-way latency.

## Latency sources

During an active connection, prefer the pinned common-c `LiGetEstimatedRttInfo` ENet control-channel estimate when it succeeds. Call only inside the connection lifecycle; serialize access/cancellation with stop and reconnect. Check units, variance semantics, source timestamp and thread-safety in D0/N0 before implementing the adapter. Polling every five seconds does not prove that ENet obtained a new sample every five seconds: keep collection and source-measurement time separate and mark source freshness unknown if unavailable.

For idle hosts, schedule one lightweight request per refresh to an existing, source-verified host service supported by that host. Reuse paired/trusted transport and established port discovery; do not assume a new UDP echo service or require raw ICMP privileges. Label a service response measurement as such because it includes service processing/transport setup. Reuse connections where supported and report cold connection setup separately. Unsupported probes are not proof that an otherwise usable host is offline.

The exact idle request and capacity-test protocol are source-verification tasks, not invented APIs. Capability-detect them; standard Moonlight-compatible hosts remain usable when an optional probe is unsupported.

## Bandwidth evidence and traffic budget

Refresh telemetry every five seconds without running a saturating speed test every tick. During a stream, count unique validated payload at receive/reassembly boundaries before decode drops, with wire-byte/loss/FEC counters separately; if accounting is not observable, label the measured boundary and do not fabricate goodput. This measures delivered traffic and congestion symptoms, not spare capacity.

A capacity estimate requires host cooperation or an existing verified bounded transfer endpoint. Plan a pre-session test or a user-requested network test, default maximum **2 seconds / 64 MiB per direction**, with cancellation. These are provisional traffic limits, not a promised measurement accuracy. Show transfer duration, actual bytes, loss and whether a byte/time cap limited inference. A TCP/service transfer cannot by itself qualify UDP streaming: combine sufficient useful-rate evidence with same-route live UDP validation. An endpoint with a server-side rate limit is not a measurement of the unconstrained network.

While streaming, prefer passive counters and existing control statistics. Any optional supported lightweight probe is bounded to **128 KiB per five-second interval globally**, with no overlapping transfers and immediate suspension on congestion/decoder pressure. This low traffic budget is not enough to measure arbitrary high path capacity: report estimate unknown/stale when evidence cannot be refreshed. Do not silently launch the large test, increase the video bitrate, or sacrifice frames to keep a number looking fresh.

If the host lacks a suitable capacity-test endpoint, the UI still shows RTT and current goodput, and explicitly reports available bandwidth unknown. Choosing whether to add a host-side extension is a later implementation decision; no host code is included here.

## Scheduling and sample lifecycle

- Foreground cadence: 5 seconds, with stable per-host offsets, a global maximum of two lightweight host probes in flight, one per host, and a 2-second per-request timeout. Many hosts may delay a tick; display the actual age rather than pretending exact freshness.
- Refresh configured hosts while their list/detail is visible; keep the active host monitored during streaming. Avoid probing all saved hosts from a hidden screen. Stop timers/probes in background, on removal, or when the active host is stopped; resume with an immediate refresh.
- Keep the last 12 valid RTT samples (about one minute at nominal cadence), sample count and failures. A timeout is a failed sample, not an artificially large successful RTT. Three consecutive supported probe failures mark the monitoring state unreachable; transport unsupported/authentication errors remain distinct, and existing stream health takes precedence over one optional probe.
- Initial stale thresholds: RTT 15 seconds; capacity evidence 30 seconds. Evaluate age from the actual measurement timestamp, not display refresh. If the source timestamp is unavailable, expose that limitation rather than extending a qualification TTL through polling.
- Key records by host identity, endpoint/address family, client interface/route, direction and transport. Invalidate route evidence immediately on interface/address/route changes and reconnect; do not reuse a LAN estimate for a WAN route.
- No monotonic-clock mixing: durations use a client monotonic clock; any host timestamp requires calibration. Provide sanitized summary data, not pairing keys or persistent raw packet logs.

## Auto and live degradation

Before negotiation, Auto consumes fresh route-specific capacity and UDP evidence plus device/profile decode qualification. PyroWave still requires useful capacity headroom of at least 20%; RTT alone never satisfies it. Missing/stale evidence leads to a bounded supported preflight test or verified hardware fallback. A monitoring refresh cannot manufacture admission. The capacity TTL governs admission or a new negotiation; its expiry alone does not terminate an otherwise healthy running stream.

During streaming, refresh indicators every five seconds and track persistent route degradation across three consecutive windows (initial 15-second hysteresis), alongside actual packet loss, queue pressure and client-ready latency. Show degraded state/rejection reason; isolated jitter does not reconnect. Codec remains fixed for the session. If established session overload policy requires fallback, perform the existing single bounded renegotiation and cooldown; do not switch codecs each tick or silently reduce the requested profile. Immediate protocol/disconnection failures follow connection handling without waiting for the monitoring window.

## Planned validation

B11 covers active ENet available/unavailable, idle service supported/unsupported, timeout/auth failure, multiple hosts, IPv4/IPv6 routes, interface changes, source timestamps, stale estimates, cancellation/background, asymmetric transfer, bounded-probe caps and capacity unavailable. Compare monitor on/off on every target model with the same live content, codec and route; monitor must not cause recurring frame-budget misses or growing queues. Validate measured bytes against receiver counters and a controlled network reference. No numeric result is claimed until these physical tests run.

## Sources and related specifications

- [Pinned common-c RTT API](https://github.com/moonlight-stream/moonlight-common-c/blob/f900dd4767759c7b9d0e93bcea666b55c69ea62f/src/Limelight.h)
- [RFC 5136: network capacity, available capacity and usage](https://www.rfc-editor.org/rfc/rfc5136)
- [Auto selection](codec-selection.md), [decode performance](decoding-performance.md), [device support](device-support.md)
- [Network monitor settings specification](../configs/network-monitor.example.json)
