# Upstream sources and generated layout

| Source | Path | Pinned revision |
| --- | --- | --- |
| Moonlight iOS/tvOS | `app/Moonlight` | `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a` |
| Baseline common-c | Nested Moonlight dependency | `f900dd4767759c7b9d0e93bcea666b55c69ea62f` |
| PyroWave | `third_party/pyrowave` | `186f0393b77f7755953b5ecde994bb1cec2e4155` |

`tools/bootstrap.py` initializes and verifies sources and nested dependencies.
The original Moonlight Xcode project, relative paths and licenses are retained.
The standard common-c baseline is not replaced by the Nonary fork.

`tools/prepare_client.py` applies the [selected integration patches](../integration/README.md)
to a generated client below `build/client/`. It verifies pins even on cache hits
and refuses a reused directory with different integration inputs.
`tools/prepare_metal.py` stages the native dependency plus the Apple5 decoder
patch. Encoding retains the original Apple7 gate; the decoder-only factory adds
portable Apple5 capability selection. No Qt/Granite/Vulkan application dependency
is imported into the tvOS target.

[Protocol provenance](../native/protocol/UPSTREAM.md),
[Apple decoder provenance](../native/apple/UPSTREAM.md) and
[the source manifest](../configs/upstreams.lock.json) record donors, changes and licenses.
