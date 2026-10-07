# Development status — 2026-10-07

Implementation has begun. The experimental live client path is now implemented; this is not a qualified PyroWave release.

| Area | Implemented now | Validation |
| --- | --- | --- |
| Standard tvOS app | Genuine pinned Moonlight source/project submodule, bootstrap and unsigned build command | Unsigned ARM64 device-target build passed in Mac CI with Xcode 26.6 / tvOS SDK 26.5; current-tvOS physical startup/streaming pending |
| PyroWave dependency | Genuine pinned native Metal source | Original device gate retained; Apple5 adaptation pending |
| Nonary framing | Record and length-prefixed parser, loss metadata and structural/payload bounds | 71 directed checks plus 10,000 random malformed frames, ASan/UBSan |
| Codec interoperability | Real pinned CPU layout, packetization and decoder parser | 12 geometry/chroma combinations through 4K, CPU only |
| Video test script | Generated motion/gradient/text clip or selected input; real codec invocation; output/count/framing checks; failure reports | Actual FFmpeg H.264/HEVC encode/decode checks at 320x180/30 and 1280x720/60 |
| Metal offline harness | Native encoder, offline file writer, decoder feeding validated spans, YUV reconstruction and optional GPU timestamps | Native source compiled successfully in Mac CI; the exposed Metal device failed the upstream support gate, so GPU execution was explicitly skipped |
| App renderer/protocol dispatch | Selective RTSP/SDP and complete-frame delivery patches; bounded asynchronous Metal decoder, private YUV textures and GPU presenter; explicit Debug request | Integrated unsigned ARM64 target compiled in CI with Xcode 26.6 / tvOS SDK 26.5; live streaming and physical correctness pending |
| Runtime admission / scheduling | Exact single SDP bitstream identity; two GPU slots plus one latest pending frame; BT.601/709 full/limited-range conversion | 100,068 portable runtime checks passed under ASan/UBSan in CI; actual presenter MSL/render pipeline compiled on the Mac; no GPU execution claim |
| Auto preference / host monitor / debug reconnect | Pending | Design and templates available; no runtime claim |

The Linux runtime here has no accessible Metal/Vulkan GPU and no Xcode. The native harness compiled successfully in Mac CI. Its probe reported `device_available: true` and `native_backend_supported: false`; encoding/reconstruction steps were explicitly skipped. Hosted Mac tests do not establish Apple TV performance. The first CPU smoke report is committed with GPU metrics null and Auto qualification false. LeakSanitizer cannot inspect this sandbox’s process tree; the local sanitized run disables leak detection while retaining address and undefined-behavior checks. The normal CI sanitizer run does not disable leak detection.

The complete [CI run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37622987361) passed for implementation commit `4f4a947c2515e0abb5250ff955e30e6dbed44272`: portable sanitizers, seven Python runner tests, CMake/CTest, CPU video encoding, Metal compilation and unsigned Moonlight TV compilation. A [sanitized check record](../benchmarks/results/2026-10-07-ci-checks.json) captures the evidence and limitations. Compilation against SDK 26.5 does not validate execution on the current tvOS 27.

Next: execute the real Metal round trip on supported Apple Silicon, then implement/validate the Apple5 shader path and wire the decoder into the actual tvOS protocol/renderer. Physical device, source/load comparability and exact profile gates remain required for Auto.

The new client integration is described in [experimental client testing](experimental-client.md). Standard Auto remains unchanged. Incomplete frames still follow stock common-c loss handling; the Nonary partial-frame transport patches have not yet been imported. These complete-frame patches do not replace common-c with the divergent donor fork.

The [integrated client CI run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37654083647) passed for implementation commit `369084a5ef3d323fe180c3830c045a4da50fe81d`: integrated unsigned ARM64 Moonlight TV compilation, actual live presenter shader/pipeline compilation, native offline harness compilation, 100,068 runtime checks, parser/CPU codec tests, seven Python tests, three CTest cases and baseline CPU video encoding. The codec GPU round trip remains explicitly skipped because the Mac device does not pass the upstream Apple7 gate. See [the sanitized integration check record](../benchmarks/results/2026-10-07-live-integration-ci.json).
