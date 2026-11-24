# Practical tests, in plain language

Test report: 2026-11-24. The new checks below ran on the Mac using the actual
client queue/profile helpers and GPU packing code. Earlier physical A12 results
are shown separately. They are not interchangeable.
[Machine-readable results and source hashes](../benchmarks/results/2026-11-24-practical-checks.json)

## What did we check?

| Practical question | Result | What this proves |
| --- | --- | --- |
| Does the 10-bit path keep its extra precision? | **1,024 of 1,024 levels preserved**, in all 8 cases | The output-packing step keeps the tested codes; it does not certify HDR on a TV |
| Does 4:4:4 keep the colors of adjacent pixels separate? | **4 of 4 one-pixel color-pattern cases passed**, with every sample exact | The output buffer keeps full-resolution chroma; host compression and HDMI output were not tested |
| Does the waiting list grow when too much work arrives? | **100,000 extra frames:** at most 2 processing + 1 waiting; the next selected frame was the newest | The queue stays bounded in this logic test; the replacement count is not a live-stream drop rate |
| Can the output-buffer pool fill up and recover? | **3-buffer limit respected; allocation recovered** after release | The pool handles this pressure/recovery scenario without growing indefinitely |
| Can an unsupported profile silently become another format? | **4 compatible matches accepted, 12 mismatches refused** | The profile helper adds no unrequested fallback; a real host handshake still needs testing |
| Can HDR information remain on a reused SDR buffer? | **Correct PQ/SDR tags; HDR metadata removed on SDR reuse** | The tested metadata transition is correct in memory; physical TV mode switching was not tested |

For the precision test, we sent every code from 0 to 1,023 into the actual GPU
packing code and read the result back. For 4:4:4, the two color components
alternated in columns one pixel wide. Together the eight cases checked **294,912
component values**, with no mismatch. The queue test held two slots busy: 99,999
pending frames were replaced, and the next selected frame was number **100001**,
the most recently submitted one.

The GPU was the Mac's AMD device; its driver-reported name is in the JSON report.
**These new tests are not Apple TV measurements.** They inject known samples into
the output step; they do not encode a game on a PC and stream it over a network.
All portable parser/runtime tests also passed, including 34 Python tests.

## How much time did the physical A12 take?

These are **earlier physical Apple TV A12 measurements from 2026-11-24**, not a new
run of the checks above. The new device attempt in this update was refused by
tvOS because the Apple TV was asleep, including an attempted background launch.
No timing is invented for that attempt.

A frame is one image in the video. At 60 frames per second, a new source image
arrives every **16.67 milliseconds**. Here we measured one synthetic 4K SDR frame
from local CPU preparation through GPU decoding and color conversion, waiting for
completion before starting the next frame. Network and TV display time are absent.

| Synthetic payload budget at 4K | Typical time: 50 out of 100 frames at or below this | Slow-end time: 95 out of 100 frames at or below this |
| --- | --- | --- |
| 150 Mbps | 15.28–21.39 ms | 20.40–27.04 ms |
| 300 Mbps | 19.85–26.53 ms | 27.28–32.49 ms |
| 500 Mbps | 23.78–30.34 ms | 31.09–36.20 ms |
| 1000 Mbps | 27.28–41.11 ms | 36.81–44.56 ms |

Each cell spans the observed values from **two runs**, each with 100 timed frames
and 20 warmup frames. These spans are not confidence intervals. The raw report
also retains the 99-out-of-100 values. A budget of 1,000 Mbps here describes the
synthetic workload size; it does not mean a real stream delivered 1,000 Mbps.
[Full physical-device record](../benchmarks/results/2026-11-24-a12-offline-device.json)

In these runs, larger payloads took more work. The numbers are **not**
controller-to-screen latency, a 60 FPS certification, an HDR/4:4:4 benchmark, or a
win over HEVC. The live client can overlap stages, while this test processes frames
serially. GPU clocks and system load also vary. Do not turn `1000 / time` into a
claimed live-stream frame rate.

Separately, the earlier [physical A12 color-profile check](../benchmarks/results/2026-11-24-a12-color-profiles.json)
passed all four decoder profiles at two small resolutions and 294,912 packing
comparisons. That earlier pattern checked eight sample codes; the new complete
1,024-level ramp has so far been run on the Mac only.

## What should a player conclude?

The output buffers preserve the tested 10-bit values and fine chroma pattern, and
the queue does not retain an ever-growing backlog under the simulated overload.
The earlier A12 tests prove that the tested decoder/packing work executes on that
physical device. None of these checks measures a complete playable session.

To answer “Does HDR look right on my TV?”, “Can it hold 4K60 for half an hour?” or
“Is it faster than HEVC?”, we still need a real host, a compatible TV and matched
repeatable sessions. [Next steps and completion criteria](ROADMAP.md)

## Reproduce the checks

On a Mac with Xcode, from the repository root:

```sh
python3 tools/run_portable_tests.py --sanitize
xcrun clang++ -std=c++17 -O2 -fobjc-arc -Wall -Wextra -Werror -I native/apple tools/check_video_profiles.mm -framework Metal -framework Foundation -framework AVFoundation -framework CoreVideo -framework CoreMedia -framework QuartzCore -o /tmp/check-video-profiles
/tmp/check-video-profiles
```

The GPU check must report `gpu_available: true`; a no-GPU skip is not a passed GPU
execution test. Look for `preserved_10bit_levels_per_case: 1024`, `ramp_cases: 8`
and `single_pixel_444_cases: 4`. The physical diagnostic uses the same signed Xcode
project; see [device instructions](local-testbenches.md#offline-a12-device-diagnostic).
Keep raw local logs in ignored `benchmarks/local/`, publish sanitized summaries,
and restore the normal app after any temporary device diagnostic.
