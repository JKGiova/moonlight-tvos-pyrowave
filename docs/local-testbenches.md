# Local CPU and Metal testbenches

Run the testbenches from the repository root. Results and logs go into an ignored,
timestamped directory under `benchmarks/local/`. A fresh report directory preserves
each comparison's executable, shader snapshot, source hashes and raw measurements.

```sh
python3 tools/run_local_benchmarks.py --builds
```

The build option compiles Debug and Release for both tvOS Simulator and device,
using the existing `build/client/Moonlight-Clean-Release` project. These are
unsigned build checks. The testbench itself runs on the Mac. Installation and
controller-to-screen measurements have their own evidence boundaries.

## CPU preparation

For 720p, 1080p and 4K, the generator uses the pinned CPU codec packetizer to
construct valid synthetic frames with byte budgets equivalent to 150, 300, 500
and 1,000 Mbps at 60 FPS. A frame can use less than the budget. Reported bytes
and block counts identify the actual input. These fixtures exercise coefficient
control, magnitude and sign validation.

Each sample measures allocation/copy, framing validation, codec packet ingestion
and total CPU preparation. Warm-up samples are excluded explicitly. Subsequent
samples retain their p50/p95/p99 and mean. The same synthetic data is reused to
isolate the stage. Real game streams vary in image content, compression and cadence.

For a paired comparison, compile the prior framing implementation into a separate
namespace and alternate reference/candidate order for every sample in one process.

```sh
mkdir -p benchmarks/local/reference
git show f32ef2e:native/protocol/pyrowaveframing.cpp > benchmarks/local/reference/framing.cpp
python3 tools/run_local_benchmarks.py --cpu-only --iterations 500 --warmup 50 --compare-framing benchmarks/local/reference/framing.cpp
```

The paired series measures validation alone. Reference and candidate must both
accept every frame with the expected block count. The regular preparation series
is measured separately.

## Apple5 kernel

On macOS with a Metal device, the runner compiles the actual portable dequant
source and repeats the eight canonical coefficient fixtures over aligned 720p,
1080p and 4K coefficient extents. Each case performs one dispatch per sample.
GPU timestamps cover that command's execution. CPU command submission is a
separate series. A readback outside timed work checks every output coefficient
against the independent fixture reference.

This isolates one synthetic coefficient band. Its workload and elapsed time have
a different scope from the whole video decoder. Reports identify the Metal device,
thread width, coefficient extent, fixture, sample count and maximum error.
A missing GPU produces an unavailable record.

## Complete offscreen decoder

A host-only lab device uses the pinned decoder's internal pipeline helpers,
portable dequant, default FP16 storage/FP32 math, mirrored sampling and real
decoder API. The tool assembles this lab device directly. The report also queries
and retains the host's production backend candidacy.

Two zero-coefficient profiles, 128x128 and 320x180, must reconstruct uniform
0.5 YUV planes within one R8 code value. Twelve additional synthetic cases cover
the three resolutions and four byte budgets. Decode and color conversion use
separate command buffers on the same queue, private YUV planes and the actual
presenter shader. Per-frame waits serialize the offline experiment.

GPU decode, GPU conversion, CPU preparation and GPU-end Ready have separate
boundaries. Ready starts immediately before framing validation and ends at the
offscreen conversion's GPU end. Input ownership/copy is measured by the separate
CPU series. Fixture creation and readback are outside timed work. This experiment
has no drawable acquisition, display compositor, live transport or physical panel.

The final YUV and BGRA output bytes contribute to an FNV-1a checksum. A matched
reference report checks all 14 full-decoder checksums before recording timing
deltas. Benchmark source hashes, case identities and host GPU must agree.

```sh
git show f32ef2e:native/apple/shaders/wavelet_dequant_apple5.metal > benchmarks/local/reference/dequant.metal
python3 tools/run_local_benchmarks.py --framing-source benchmarks/local/reference/framing.cpp --shader-source benchmarks/local/reference/dequant.metal --output-dir benchmarks/local/baseline
python3 tools/run_local_benchmarks.py --compare-framing benchmarks/local/reference/framing.cpp --compare-report benchmarks/local/baseline/report.json --builds --output-dir benchmarks/local/candidate
```

The lab path permits a host GPU experiment independently of the production
Apple-family factory. Its outputs carry `physical_apple_tv_tested=false`.
The app and standard offline tool continue to use normal production admission.
The [local result record](../benchmarks/results/2026-11-23-local-testbenches.json)
identifies the measured hardware and limits of the current comparison.

## Local and CI checks

The existing sanitizer/mutation suites check framing semantics. The GPU fixture
checker validates portable coefficients and compiles all six inverse-wavelet
variants. The presenter checker verifies split-submission texture dependencies,
color and orientation. The local build matrix checks both simulator and device
SDKs without deploying to a physical Apple TV.

CI runs short correctness-focused CPU and host Metal benchmark samples and retains
JSON reports and diagnostic logs as artifacts. Timing values are recorded with
their hardware and sample counts. Physical A12/A15 performance qualification
requires matched device measurements. [Timing definitions](decoding-performance.md)
