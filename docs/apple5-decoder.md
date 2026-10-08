# Experimental Apple5 decoder

Implemented on 2026-10-08; physical PyroWave correctness and latency are still
unverified. The user's successful standard-client smoke test on an A12 Apple TV
does not qualify this decoder. Normal Auto remains unchanged.

## Backend choice

`pw_decoder_device_create` probes the actual GPU. Apple5/6 use
`metal-portable-apple5`; Apple7 and later retain `metal-native-apple7`.
Both must successfully compile all decode pipelines, meet per-pipeline thread
and static threadgroup memory limits, allocate their textures and create the
sampler. Candidate detection alone is not success. Intel/AMD Mac GPUs remain
excluded from live codec admission and offline full decoding. Encoding still
uses the original Apple7 gate.

The portable path replaces dequant SIMD prefix sums/shuffles. Its 128 threads
scan eight contributions per group and then sixteen group totals in shared
memory, with uniform barriers and no dependency on SIMD width. The upstream
64-thread iDWT is unchanged; it already uses threadgroup storage/barriers.
Portable libraries compile with MSL 2.2. The wire identity is still `186f0393`.
FP32 math with FP16 pyramid storage remains the default, not a new quality mode.

Apple's [feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
map A12 to Apple5 and place SIMD permute at Apple6 and SIMD reduction at Apple7.
Replacing those operations is necessary; lowering a family check alone would
leave unsupported shader requirements. See [source provenance](../native/apple/UPSTREAM.md).

## Correctness checks

`tests/dequant_fixture.hpp` builds canonical synthetic coefficient records with
known expected output. Eight cases cover sparse/full/zero tile ballots,
0–15 base planes, all local plane controls, zero magnitudes, alternating signs,
cross-group sign offsets, quantization boundaries, multiple 32x32 blocks, a
missing block and output into a nonzero array layer. Both the framing validator
and pinned CPU parser must accept them before shader execution. These are
controlled coefficient fixtures, not GPU-encoded video.

On a Mac with a Metal GPU:

```sh
python3 tools/build_engine.py
python3 tools/embed_apple5_shader.py --check
python3 tools/build_decoder_check.py --run
```

This executes the actual portable shader and checks 32,768 FP32 coefficients
against the fixture reference, with absolute tolerance `1e-4` plus relative
tolerance `1e-5`. All six upstream iDWT precision/DC pipeline variants must
compile. On Apple7+, the native dequantizer also checks the same expected
coefficients. On another Mac GPU only the portable kernel is executed; that
numerical check does not enable the full codec or establish Apple TV performance.
A missing GPU is reported as skipped, not passed execution.

When the GPU passes decoder candidate admission, the checker also creates the
real portable decoder device and runs two complete all-zero wavelet frames
(128x128 and 320x180) through parser, upload, dequant and all iDWT levels into
private YUV textures. Each reconstructed plane must be uniformly normalized
0.5 (127 or 128 after R8 UNORM conversion). This tests allocation, padded
geometry, sampler and inter-pass ordering, without requiring a GPU encoder.
On a GPU outside the live Apple-family admission gate this full-decoder check
is skipped and reported as zero tested profiles; the isolated kernel check
can still execute. It is a synthetic correctness smoke test, not a latency
benchmark or a real-video round trip.

For real encoded-frame comparison on a supported Apple Silicon Mac:

```sh
build/metal/pyrowave-video decode clip.pyrowave native.y4m native-metrics.json
build/metal/pyrowave-video decode-portable clip.pyrowave portable.y4m portable-metrics.json
```

Use the same real PyroWave file, pin and precision. Compare reconstructed output
and profile-specific errors as well as the original Y4M; successful completion
alone is insufficient. Offline timestamps include decoder command execution;
readback/waits are confined to these testing tools.

## Physical next gate

Install the fresh app described in [experimental testing](experimental-client.md).
Select PyroWave manually, keep SDR/HDR-off at 720p60 initially, and check that
the statistics overlay names `metal-portable-apple5` on A12. Record negotiated
codec, visual correctness, audio/input, ready p50/p95/p99, combined GPU time,
queue replacements, parser failures and presentation drops. Repeat at 1080p60,
then compare with HEVC using the same scene/bitrate. This is bring-up evidence;
the [full performance gates](decoding-performance.md), physical A15 comparison,
4K and thermal tests remain required before Auto qualification.
