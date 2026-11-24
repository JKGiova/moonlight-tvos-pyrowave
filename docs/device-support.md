# Apple TV devices and evidence

The repository's reviewed device manifest covers the second-generation Apple TV
4K and both third-generation variants. This records the existing scope and
backend implementation; it is not a claim of physical validation on every model.

| Model | Model number | SoC / Metal family | Decoder candidate | Recorded physical evidence |
| --- | --- | --- | --- | --- |
| Apple TV 4K, 2nd generation | A2169 | A12 / Apple5 | Portable Apple5 | Owner-reported 4K60 PyroWave runs and overlay screenshots |
| Apple TV 4K, 3rd generation, Wi-Fi | A2737 | A15 / Apple8 | Native Apple7-or-later | None recorded |
| Apple TV 4K, 3rd generation, Wi-Fi + Ethernet | A2843 | A15 / Apple8 | Native Apple7-or-later | None recorded |

The single **Moonlight TV** app target checks real GPU capabilities and pipeline
creation. The manifest is not a runtime qualification allowlist. Apple7-or-later
candidacy follows the backend checks; it does not prove A15 throughput or latency.
A12 observations do not establish A15 results, and neither A15 variant has a
recorded qualification result.

The owner reported operation on A12/tvOS 27. Historical unsigned builds used
Xcode 26.6 and tvOS SDK 26.5. A successful SDK build is separate from device
execution. The manifest's scope was reviewed on 2026-10-07; this page makes no
new compatibility claim about other Apple TV models or the latest OS release.

The client implements 8-bit SDR and 10-bit HDR10 profiles in 4:2:0 and 4:4:4.
The 10-bit presentation path requires tvOS 17+ and successful CoreVideo surface
admission. Live HDR output and 4:4:4 performance are not qualified on any model.
HDR10+ is not advertised; the A12 model does not list HDR10+ output support.
See [color profile implementation and limits](video-profiles.md).
There is no qualified automatic PyroWave
codec admission for any model. [Device observations](development-status.md#apple-tv-device-observations)

## References

- [Device manifest](../configs/devices.json)
- [Apple model identification](https://support.apple.com/en-gb/101605)
- [A12 model specifications](https://support.apple.com/it-it/111922)
- [A15 model specifications](https://support.apple.com/it-it/111839)
- [Metal feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
- [Apple5 decoder implementation](apple5-decoder.md)
