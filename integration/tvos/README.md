# tvOS app boundary

Implemented experimental integration: selective MainFrameViewController admission, Connection negotiated-format dispatch, renderer ownership and statistics overlay. The genuine project is preserved in app/Moonlight; tools/prepare_client.py applies integration/patches to a generated client checkout. Normal codec preferences and qualified Auto are still pending. See [experimental client testing](../../docs/experimental-client.md).

Plan a single app for every Apple TV in [the device matrix](../../docs/device-support.md), including both third-generation variants. Runtime feature probes choose decoder paths; no second-generation-only build. Minimum deployment target and SDK/toolchain validation belong to D0 after implementation is authorized.

Planned host list/detail UI shows RTT in ms, current receive goodput in Mbps, available-bandwidth estimate or unknown/stale state, and last measurement age. Refresh from monitor snapshots every five seconds without blocking focus, settings or stream presentation.

Planned debug-only test launch uses a local profile to reconnect to the explicitly selected paired Vibeshine host and chosen app. No auto-pairing bypass or global autostart default. See [Vibeshine testing](../../docs/vibeshine-testing.md).
