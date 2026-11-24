# Integration patches

The standard generated client uses these patches in order:

| Patch | Applied to | Purpose |
| --- | --- | --- |
| `moonlight-ios.patch` | Moonlight app | Codec preference/admission, renderer dispatch, project sources and base overlay |
| `moonlight-cleanup.patch` | Moonlight app | Fixed-array constants, spinner/bitmap and build cleanup |
| `moonlight-tvos-bitrate.patch` | Moonlight app | Bitrate Auto menu and manual values through 1,000 Mbps |
| `moonlight-pyrowave-scheduling.patch` | Moonlight app | Frame-wait worker, GPU-end Ready and four-stage overlay |
| `moonlight-common-c.patch` | Baseline common-c | Selective PyroWave negotiation and complete-frame transport |
| `common-c-cleanup.patch` | Baseline common-c | Guarded control-thread initializations and platform warning cleanup |
| `common-c-bitrate.patch` | Baseline common-c | Resolve bitrate Auto after codec negotiation |
| `moonlight-video-profiles.patch` | Patched app and common-c | Explicit 420/444, 8/10-bit profiles, exact-profile enforcement and HDR metadata forwarding |

`tools/prepare_client.py` applies these to a generated copy below `build/client/`.
`tools/prepare_metal.py` separately applies `pyrowave-metal-apple5.patch` to the
staged native codec. The source submodules and their license notices are retained.

`moonlight-host-dashboard.patch` is retained as reference and is not in the
standard preparation list. The standard app uses Moonlight's normal app list.

- [tvOS app](tvos/README.md)
- [Metal decoder](metal/README.md)
- [Protocol](protocol/README.md)
- [Codec selection](selection/README.md)
- [Reference monitor](network/README.md)
