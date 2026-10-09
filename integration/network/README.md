# Host dashboard monitoring

Implemented in `native/apple/MLHostNetworkMonitor`, `MLHostProbeSession`,
`MLHostPing` and `MLHostDashboardView`, with policy helpers in
`native/client/host_monitor_policy.hpp`. The selective tvOS patch is
`integration/patches/moonlight-host-dashboard.patch`.

Five-second monitoring is limited to the selected PC dashboard. Launch/resume
waits for cancellation; no monitor runs during streaming. The optional paired
HTTPS test follows Vibeshine's advertised 32 MiB payload and quota protocol.
Read [the behavior, limits and physical test guide](../../docs/host-network-monitor.md).
