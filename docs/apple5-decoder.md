# Apple5 Metal decoder

The portable decoder is implemented and has owner-reported live A12 streaming
observations. These observations are separate from the synthetic GPU correctness
checks below and do not establish release qualification. Codec Auto retains the
standard Moonlight path. [Device observations](development-status.md#apple-tv-device-observations)

[CI](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37809452393)
passed for `5203f4bda439272f4b0bf5898f79c3817ea662f4`: the actual portable GPU
kernel matched all 32,768 reference coefficients exactly, all six iDWT pipelines
compiled, and the full portable decoder reconstructed two uniform synthetic
profiles correctly. The unsigned tvOS target and both Metal harness build paths
also passed. [Recorded evidence](../benchmarks/results/2026-10-08-apple5-ci-checks.json)
records real-video, native/portable comparison, physical-device and latency tests
as unavailable in that CI run.

## Backend choice

`pw_decoder_device_create` probes the actual GPU. Apple5/6 use
`metal-portable-apple5`; Apple7 and later retain `metal-native-apple7`.
Both must successfully compile all decode pipelines, meet per-pipeline thread
and static threadgroup memory limits, allocate their textures and create the
sampler. Candidate detection alone is not success. The standard factory requires Apple-family
capabilities for complete decoding. The [host testbench](local-testbenches.md)
assembles a separate lab device for synthetic offscreen experiments. Encoding still
uses the original Apple7 gate.

The portable path replaces dequant SIMD prefix sums/shuffles. Sixteen lanes
compute tile byte offsets from separate shared cost storage. All 128 threads
then scan sign counts using groups of eight and sixteen group totals. Four
uniform barriers order these phases, reduced from seven after host coefficient
and timing comparisons. The algorithm is independent of SIMD width. The upstream
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

## Physical observations

The owner reported a 30-minute 4K60 A12 session at a 150 Mbps setting with zero
queue drops, followed by separate screenshots with queue replacements and higher
Ready p95. [The observation record](development-status.md#apple-tv-device-observations)
keeps these sessions separate. No matched HEVC comparison, physical A15 result or
decoder-only GPU timing is recorded. The current combined GPU time includes color
conversion. [Timing boundaries](decoding-performance.md)
