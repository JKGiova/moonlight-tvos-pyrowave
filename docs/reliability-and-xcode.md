# Reliability checks and Xcode diagnostics

This page records completed changes and historical diagnostics. A successful
build or analyzer exit is not a physical Apple TV performance result and does
not establish that all analyzer findings were resolved.

## Recorded CI evidence

The [reliability CI run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37894111446)
passed five jobs for `9c9899dd2b9b7f7a85d5d62d847aaa059c4c4081`.
The [sanitized record](../benchmarks/results/2026-10-09-reliability-ci-checks.json)
contains device Debug/Release, simulator, parser/runtime, GPU fixture and presenter
results. Device builds had zero errors and 19 warning occurrences each; the
simulator had zero errors and 35 warning occurrences. The analyzer reported 20
findings in upstream sources. Those counts describe that revision.

The initial dashboard run at `e7f60fc` failed with `ld: library 'dns_sd' not found`.
The later correction removed the explicit standalone DNS library input and added
native DNS/ICMP linkage/loopback checks. The current default generated app excludes
the dashboard patch. The [post-merge CI at f57c5ab](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/44893326699)
passed five jobs. Current results belong to their exact [Actions revision](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions).

## Implemented reliability changes

- Renderer initialization is published under its submission/statistics/stop lock;
  setup cannot revive an already stopped session.
- Timing snapshot sorting runs outside the submission lock.
- An autorelease pool drains worker temporaries per frame. Completion callbacks
  retain the runtime until submitted GPU work finishes.
- Preparation checks exact revisions, tracked modifications and nested gitlinks,
  including on cache hits; existing generated signing edits are preserved.
- Queue tests cover pending release and retained in-flight ownership across stop.
- Parser coverage includes 10,000 malformed frames and 10,000 valid-record
  mutations, with accepted mutations checked against the pinned CPU parser.
- The presenter checker executes the actual shader for 25 color/range/orientation
  cases and 3,200 pixels. It measures output correctness, not display timing.
- CI records full Xcode logs, structured diagnostics and result bundles, including
  failed builds. Package-manager waits are bounded and installed FFmpeg is reused.
- Cleanup patches initialize guarded control-thread values, use fixed enum array
  extents, update spinner styles and cast mixed enum flags. The empty Windows-only
  object is excluded from the generated Apple build.

## Historical analyzer findings

The recorded run reported the following upstream findings. They are diagnostic
observations, not proof that the owner's live stream hit the indicated path.

| Findings | Recorded source assessment |
| --- | --- |
| Two apparent stack frees in `VideoDepacketizer.c` | Direct delivery uses stack storage and queued delivery uses heap storage; analyzer could not establish the capability invariant across callbacks |
| Null FEC-list head in `RtpVideoQueue.c` | Analyzer did not prove the count/head invariant through recovery |
| Null `localAddress` in ENet `unix.c` | Optional-address output handling raised an alert on the Apple conversion branch |
| Possible RTSP option leak | Ownership transfer through `insertOption` was not established by analysis |
| Nine `unix.Errno` findings | Failure codes cross helper/callback boundaries |
| Three nullable UIKit arguments | Optional subviews and touch-removal paths raised nullable-argument findings |
| Three dead stores in ENet | QoS/compression assignments were overwritten or unused |

The historical compiler diagnostics also included deprecated certificate/window,
button and launch APIs and pinned-parser signedness warnings. The repository does
not claim a clean analyzer report or completion of those API migrations.

## Collecting diagnostics

On a Mac with initialized pins, use a fresh generated client:

```sh
python3 tools/prepare_client.py --client-dir build/client/Moonlight-check
python3 tools/build_tvos.py --client-dir build/client/Moonlight-check --sdk appletvos --configuration Debug
python3 tools/build_tvos.py --client-dir build/client/Moonlight-check --sdk appletvos --configuration Release
python3 tools/build_tvos.py --client-dir build/client/Moonlight-check --sdk appletvsimulator --configuration Debug
python3 tools/build_tvos.py --client-dir build/client/Moonlight-check --sdk appletvos --action analyze
```

Each invocation records `xcodebuild.log`, `diagnostics.json` and `result.xcresult`
under a timestamped `build/xcode/<configuration>-<sdk>-<action>/` directory. CI
retains these artifacts even on failure. Local logs may contain machine paths and
need review before publication. No hosted job accesses the owner's paired host or
measures physical Apple TV latency. [Device evidence](development-status.md)
