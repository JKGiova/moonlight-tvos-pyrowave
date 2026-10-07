# tvOS app boundary

Planned changes: codec preferences, MainFrameViewController selection, Connection negotiated-format dispatch, renderer ownership, settings and statistics. No Objective-C source or Xcode project is present yet.

Plan a single app for every Apple TV in [the device matrix](../../docs/device-support.md), including both third-generation variants. Runtime feature probes choose decoder paths; no second-generation-only build. Minimum deployment target and SDK/toolchain validation belong to D0 after implementation is authorized.

Planned host list/detail UI shows RTT in ms, current receive goodput in Mbps, available-bandwidth estimate or unknown/stale state, and last measurement age. Refresh from monitor snapshots every five seconds without blocking focus, settings or stream presentation.
