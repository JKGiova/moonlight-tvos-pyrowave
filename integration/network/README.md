# Reference host monitor

The retained dashboard patch uses `native/apple/MLHostNetworkMonitor`,
`MLHostProbeSession`, `MLHostPing`, `MLHostMonitorBarrier` and
`MLHostDashboardView`, with policy helpers in `native/client/host_monitor_policy.hpp`.

`moonlight-host-dashboard.patch` is not applied by standard client preparation.
The standard generated app has the normal Moonlight app list and no dashboard
bandwidth test. The reference implementation limits five-second checks to the
selected foreground dashboard and drains probes before streaming.
[Implementation details and test coverage](../../docs/host-network-monitor.md)
