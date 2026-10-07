# Development status — 2026-10-07

Implementation has begun. This is a working foundation, not a completed PyroWave tvOS app.

| Area | Implemented now | Validation |
| --- | --- | --- |
| Standard tvOS app | Genuine pinned Moonlight source/project submodule, bootstrap and unsigned build command | Sources/pins verified here; Mac CI build requested; physical startup/streaming pending |
| PyroWave dependency | Genuine pinned native Metal source | Original device gate retained; Apple5 adaptation pending |
| Nonary framing | Record and length-prefixed parser, loss metadata and structural/payload bounds | 71 directed checks plus 10,000 random malformed frames, ASan/UBSan |
| Codec interoperability | Real pinned CPU layout, packetization and decoder parser | 12 geometry/chroma combinations through 4K, CPU only |
| Video test script | Generated motion/gradient/text clip or selected input; real codec invocation; output/count/framing checks; failure reports | Actual FFmpeg H.264/HEVC encode/decode checks at 320x180/30 and 1280x720/60 |
| Metal offline harness | Native encoder, offline file writer, decoder feeding validated spans, YUV reconstruction and optional GPU timestamps | Source written; Mac compile/GPU execution still need verification |
| App renderer/protocol dispatch | Pending | No PyroWave streaming in the app yet |
| Auto preference / host monitor / debug reconnect | Pending | Design and templates available; no runtime claim |

The Linux runtime here has no accessible Metal/Vulkan GPU and no Xcode. The native GPU harness is not declared tested here; hosted Mac CI compilation does not establish Apple TV performance. The first CPU smoke report is committed with GPU metrics null and Auto qualification false. LeakSanitizer cannot inspect this sandbox’s process tree; the local sanitized run disables leak detection while retaining address and undefined-behavior checks. The normal CI sanitizer run does not disable leak detection.

Next: verify Mac builds, execute the real Metal round trip on supported Apple Silicon, then implement/validate the Apple5 shader path and wire the decoder into the actual tvOS protocol/renderer. Physical device, source/load comparability and exact profile gates remain required for Auto.
