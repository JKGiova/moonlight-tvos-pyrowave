# Physical A12 latency investigation

Two additional offline runs on the actual Apple TV 4K second generation use the
production factory and 14 synthetic profiles, with 100 measured frames and 20
warmup each. One preserves ordinary split submission; the control waits for decode
to complete before submitting conversion. Decoder math/profile is unchanged.
All 28 output checksums match, and thermal state is nominal before/after both runs.
[Data, source hashes and sample timelines](../benchmarks/results/2026-11-24-a12-timing-investigation.json)

## Findings

The normal 4K/1,000 Mbps sample has these means, in milliseconds:

| Measurement | Mean |
| --- | --- |
| Framing validation | 5.734 |
| Codec packet preparation | 1.380 |
| Decode command encoding, allocation/upload | 0.445 |
| Decode commit call | 0.066 |
| Decode command-buffer interval | 20.676 |
| Conversion command-buffer interval | 22.921 |
| Overlap between buffer intervals | 20.663 |
| Span of both buffer intervals | 22.933 |
| Conversion end minus the later of decode end/conversion start | 2.229 |
| Entire offline frame wall time | 31.510 |

These are matched per-frame measurements. The CPU phases sum to the recorded
preparation duration. Raw GPU boundaries, relative to frame arrival, prove that
the two command-buffer intervals overlap. Their sum double-counts overlapping
time. The last statistic above the wall time is a post-decode tail, not a pure
shader execution counter.

Apple defines [GPUStartTime](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)
and [GPUEndTime](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime)
as command-buffer execution boundaries. These APIs do not identify individual
encoder or fragment-shader execution boundaries. Attributing the whole conversion
buffer interval to color-conversion arithmetic is incorrect here.

When the control submits conversion only after decode completion, measured overlap
is zero in every frame. Its 4K conversion interval means are 2.50–2.68 ms across
the four payload budgets, while decode interval means remain 15.96–22.77 ms.
The CPU fence changes scheduling and adds overhead: this is a diagnostic control,
not a candidate optimization or a fair speedup comparison between the two runs.

## What explains the earlier result

Reducing 42 dequant dispatches to 13 attacks CPU submission overhead. In the
profiled run, the entire command-encoding phase is only 0.445 ms and commit is
0.066 ms, while the decode command-buffer interval is 20.676 ms and validation is
5.734 ms. Fewer API calls therefore cannot remove most of this frame's latency.
The variation in preparation is not explained by a large commit-call stall in
these samples. Clock frequency, scheduling, shared memory bandwidth and system
GPU activity were not isolated, so none is established as the cause of variation.

The high Color interval is partly a measurement-attribution issue. The Ready and
wall end-to-end boundaries do not add the intervals, so this finding does not
invalidate Ready or erase its actual waits. The historical live 70–74 ms Ready
still cannot be reconstructed from this offscreen workload.

## Remaining investigation

The decode command buffer contains dequant and all inverse-wavelet passes. These
measurements do not identify their individual GPU costs. Encoder-level counters
or an explicitly isolated dequant/iDWT control are needed next. A live session is
also needed for drawable/compositor waits, input queue residence and sustained
4K60. No precision, profile, resolution or validation was reduced to obtain these
results. The normal Release is restored after the temporary diagnostics.

Reproduce the temporary instrumentation with
`tools/build_device_benchmark.py --device-name YOUR_TV --timing-breakdown`.
Add `--isolate-stages` for the altered-scheduling control. Raw timeline entries are
`[decode_start, decode_end, conversion_start, conversion_end]`, in milliseconds
relative to frame receipt. Read the completion/status files as documented in
[the offline diagnostic guide](local-testbenches.md#offline-a12-device-diagnostic).
