# Reviewed sources

Review date: 2026-10-06. Revision manifest: ../configs/upstreams.lock.json.

## Verified observations

- Standard tvOS Moonlight is the moonlight-ios repository and the Moonlight TV Xcode target.
- MainFrameViewController.m constructs supportedVideoFormats. The inspected Auto branch offers hardware HEVC and H.264; it is not an external decision script.
- VideoDecoderRenderer.m uses AVSampleBufferDisplayLayer and CADisplayLink. Exact hardware decode timing is not supplied merely by timing enqueue.
- Nonary vrr18 has independent C++ framing code and PyroWave integration for Windows and Linux.
- PyroWave revision 186f0393 already includes native Metal sources and a tvOS-supported Xcode framework target.
- Its device gate requires Apple7 and its dequant shader uses SIMD operations that must be adapted for A12/Apple5.
- The Nonary bitstream identity is 186f0393. Capability/profile constants and transport framing must match the host.
- The Android reference uses a PYRW container with big-endian lengths; Nonary record/length-prefixed framing is different.
- Nonary common-c diverges from the tvOS baseline (10 ahead, 5 behind in the inspected comparison); selective patch transfer is required.
- Upstream notes limited maintenance of the Metal port. Pin its source and keep local changes documented.

## Primary links

- [Moonlight iOS/tvOS baseline](https://github.com/moonlight-stream/moonlight-ios/tree/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a)
- [Client codec selection](https://github.com/moonlight-stream/moonlight-ios/blob/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a/Limelight/ViewControllers/MainFrameViewController.m)
- [Nonary protocol](https://github.com/Nonary/moonlight-qt/blob/v6.1.0-vrr18/docs/pyrowave-protocol.md)
- [Nonary framing/decoder](https://github.com/Nonary/moonlight-qt/tree/v6.1.0-vrr18/app/streaming/video/pyrowave)
- [PyroWave Metal baseline](https://github.com/Themaister/pyrowave/tree/186f0393b77f7755953b5ecde994bb1cec2e4155/metal)
- [Apple GPU families and features](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
- [Apple TV A12 specifications](https://support.apple.com/en-us/111922)
- [Android reference](https://github.com/joemossjr16/artemis-android-pyrowave/tree/387d3a5ce1e3df8d4a4d29eec5b81a7b904926a5/app/src/main/jni/pyrowave-renderer)
- [common-c divergence](https://github.com/Nonary/moonlight-common-c/compare/f900dd4767759c7b9d0e93bcea666b55c69ea62f...d6a11bc685b41037b352a96f29d08276fe5359ba)

Verified source facts do not establish numerical A12 performance. All latency values elsewhere in this scaffold are proposed gates or goals.
