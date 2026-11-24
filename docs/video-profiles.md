# PyroWave color profiles

Implemented on 2026-11-24. These are explicit client profiles, not automatic
performance qualification. The pinned host protocol already defines the four
wire formats below; no source submodule is changed.

| Preferred Codec | Enable HDR | Negotiated profile | Output path |
| --- | --- | --- | --- |
| PyroWave 4:2:0 | Off | 8-bit 4:2:0 | Private R8 planes → Metal RGB presenter |
| PyroWave 4:4:4 | Off | 8-bit 4:4:4 | Three full-resolution R8 planes → Metal RGB presenter |
| PyroWave 4:2:0 | On | 10-bit 4:2:0 | Private R16 planes → 10-bit biplanar CVPixelBuffer → AVSampleBufferDisplayLayer |
| PyroWave 4:4:4 | On | 10-bit 4:4:4 | Three full-resolution R16 planes → 10-bit biplanar CVPixelBuffer → AVSampleBufferDisplayLayer |

The HDR toggle requests a 10-bit profile. Actual HDR follows the host's per-frame
`hdrActive` state: HDR frames carry BT.2020 primaries, the BT.2020 YCbCr matrix and
ST 2084 PQ transfer. A 10-bit session may carry SDR frames while the host display
is SDR; these frames receive SDR transfer tags. This is host state, not a client
conversion of HDR to SDR.

## Use

1. Update the client and run `python3 tools/prepare_client.py`. Keep using the
   existing `Moonlight TV` target and project.
2. In the app's tvOS Settings entry choose **PyroWave 4:2:0** or **PyroWave 4:4:4**.
   Enable HDR to request the corresponding 10-bit profile. Restart the stream
   after changing these settings.
3. For HDR10 use a compatible HDR TV/HDMI chain, enable HDR on the host display
   and use a Vibeshine build advertising the matching PyroWave profile and
   bitstream identity `186f0393`.
4. In Apple TV settings, enable **Match Content → Match Dynamic Range** if you
   want tvOS to switch HDMI output according to the stream. The client uses
   public `AVDisplayCriteria` with the sample's format description; system
   settings and the display determine the output mode. It requests the stream
   refresh rate through the same API.
5. Check the codec name: `PyroWave SDR 4:4:4` or `PyroWave 10-bit 4:4:4`, for
   example. “10-bit” identifies the negotiated format; it does not prove that
   the current scene, HDMI signal or TV picture mode is HDR.

The 10-bit presentation path requires tvOS 17 or newer and successful creation of
the requested CoreVideo/Metal surfaces. The host must advertise its base PyroWave
capability as well as the specific 10-bit/4:4:4 capability. 4:4:4 refers to the negotiated stream and client surfaces; HDMI chroma output
is controlled by tvOS and the display. Decoder family admission
remains separate from color-format support and real-time performance.

Explicit 4:4:4 or HDR requests **fail rather than downgrade** if the exact profile
cannot be negotiated or initialized. The original SDR 4:2:0 option retains its
standard-codec fallback during negotiation. There is no automatic retry after a
decoder failure; select another profile manually. Codec Auto is unchanged.

## Precision, metadata and scheduling

The existing decoder receives the correct chroma geometry and writes normalized
samples to R8 or R16 textures. In 4:4:4, Cb and Cr have the same dimensions as Y.
The 10-bit pack kernel writes `round(value × 1023) << 6` to MSB-aligned 16-bit
biplanar storage (`x420`/`xf20` or `x444`/`xf44`). This preserves the host's 10-bit
codes, including limited/full-range interpretation, without an 8-bit RGB
intermediate or a client tone-mapping pass.

The standard HDR control callback supplies mastering-display (MDCV) and
content-light (CLL) data. The renderer snapshots them with each frame and attaches
them to the pixel buffer before creating its format description. Recycled SDR
surfaces have HDR metadata removed. The 8-bit RGB path supports explicit BT.601,
BT.709 and BT.2020 matrix coefficients; HDR on an 8-bit profile is rejected.

Decode still uses two processing slots and one latest pending frame. The new
presentation pool has a hard allocation threshold of three buffers. AVFoundation
readiness applies backpressure; it does not grow an unbounded queue. A failed
AVFoundation renderer or sample construction terminates the session instead of
repeatedly flushing a black display layer. No CPU image
readback is used during streaming. Decode and packing use the same Metal queue;
slot textures remain owned until both GPU stages resolve.

For 10-bit sessions, Ready and conversion timings end at packing GPU completion.
They **exclude AVFoundation presentation, HDMI switching and TV processing**.
`presentation_timing_available` is false for this path; the client does not invent
presentation timestamps or reuse SDR measurements as HDR latency evidence.

## HDR10+ status

**HDR10+ is not implemented or advertised.** The inspected Vibeshine protocol has
HDR10 profile bits and static HDR metadata, but no negotiated transport for
per-frame SMPTE ST 2094-40 / ITU-T T.35 dynamic metadata. Changing a label or adding
a PQ tag would provide HDR10, not HDR10+.

Apple exposes `kCMSampleAttachmentKey_HDR10PlusPerFrameData` on supported systems,
but a complete implementation also needs a compatible host capture source,
versioned transport with frame association, dynamic-metadata validation, a client
sample attachment, and physical HDMI/display validation. A desktop HDR stream
cannot manufacture scene-dependent HDR10+ metadata by itself.

The existing second-generation A12 Apple TV's specifications list HDR10, HLG and
Dolby Vision, but not HDR10+. Third-generation Apple TV 4K specifications list
HDR10+. No result on the A12 can qualify HDR10+ output on another model. The
client reports `hdr10plus_transport_available: false` and offers no misleading
HDR10+ selection.

## Verification and limits

`tools/check_video_profiles.mm` executes the actual pack kernel and checks 294,912
component samples across full/limited-range, 4:2:0/4:4:4 and PQ/SDR cases. It checks
exact 10-bit codes, pixel format, static metadata, pool backpressure/recovery and
sample construction. CI compiles it with warnings as errors.
`tools/check_apple5_decoder.mm` exercises complete zero-coefficient frames in both
chroma geometries and R8/R16 outputs at 128×128 and 320×180 when the available GPU
passes the decoder admission gate. These are correctness fixtures, not encoded
video quality or performance measurements. On noncandidate Mac GPUs the full
decoder portion reports zero tested profiles.

`tools/build_device_benchmark.py --device-name <name> --video-profiles` builds a
temporary offscreen A12 correctness diagnostic in the same signed project. As
with other device diagnostics, restore the normal Release app afterward. Neither
this diagnostic nor a simulator build tests HDR HDMI output. Live HDR10, live
4:4:4 quality, sustained 4K60 throughput and input-to-display latency remain
unqualified until measured with a host and compatible display.

The [physical A12 record](../benchmarks/results/2026-11-24-a12-color-profiles.json)
reports eight complete decoder correctness profiles and eight packing cases
(294,912 component samples), all passed with exit code zero and nominal thermal
state. This tests GPU execution and sample construction on A12, not live HDR
output, HDR10+ or a 4K60 performance qualification.

## Sources

- [Pinned Vibeshine PyroWave protocol](https://github.com/Nonary/vibeshine/blob/0689b2e021d6106612a7ed72a34dacc714b7a133/docs/pyrowave-protocol.md)
- [Apple AVDisplayCriteria](https://developer.apple.com/documentation/avfoundation/avdisplaycriteria)
- [Apple HDR10+ sample attachment](https://developer.apple.com/documentation/coremedia/kcmsampleattachmentkey_hdr10plusperframedata)
- [Apple TV 4K, second-generation specifications](https://support.apple.com/en-us/111922)
- [Apple TV 4K, third-generation specifications](https://support.apple.com/en-us/111839)
- [Renderer](../native/apple/PyroWaveVideoRenderer.mm), [10-bit presenter](../native/apple/PyroWaveHDRPresenter.h)
