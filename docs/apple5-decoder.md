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

## Batched band submission

The production Apple5/6 decoder submits one dequant dispatch per component and
wavelet level. Grid Z covers the three detail bands, or all four bands at the
coarsest level. For 4:2:0 this reduces 42 dispatches to 13 (69.0% fewer), with
corresponding fewer push-constant submissions. Each band still executes the same
128-thread kernel over the same blocks and writes its original array layer.
This targets CPU/driver submission overhead on the A12 path. GPU workload,
precision, stream profile, upload ownership and iDWT ordering are preserved.
Apple7's native shader keeps the single-band path.

With an unchanged testbench, three alternating baseline/candidate simulator pairs
(300 measured frames and 50 warmup per profile per run) produce these medians
of the three individual p95 wall times. This is preparation through completion of
decode and conversion, with no drawable, compositor or network.

| 4K payload budget at 60 FPS | Baseline p95 | Batched p95 | Reduction |
| --- | --- | --- | --- |
| 150 Mbps | 1.422 ms | 1.266 ms | 11.0% |
| 300 Mbps | 1.858 ms | 1.750 ms | 5.8% |
| 500 Mbps | 2.527 ms | 2.411 ms | 4.6% |
| 1,000 Mbps | 3.977 ms | 3.838 ms | 3.5% |

All 84 repeated full-decoder output checksums match the baseline. These simulator
percentages cannot be applied to physical Apple TV latency. A later [physical A12 offline diagnostic](development-status.md#physical-a12-offline-diagnostic)
records substantial run-to-run variation and does not validate these gains on
A12; at 500 Mbps its candidate tails are higher in both runs. Live-presentation
effects remain unmeasured for this revision. The very small
simulator GPU intervals do not establish a GPU execution speedup.
[Measurements and source hashes](../benchmarks/results/2026-11-24-apple5-band-batching.json)

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

This executes the actual portable shader and checks 262,144 FP32 coefficients
against the fixture reference, with absolute tolerance `1e-4` plus relative
tolerance `1e-5`. The single-band fixtures are also dispatched in groups of
three and four bands, with distinct block permutations and a missing band. This
checks Z-to-offset/layer addressing and zero reconstruction; the old shader fails
this regression check. All six upstream iDWT precision/DC pipeline variants must
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
