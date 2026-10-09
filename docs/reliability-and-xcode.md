# Reliability review and Xcode diagnostics — 2026-10-09

This review concerns the experimental implementation, not an Apple TV release
qualification. A compiler pass cannot establish latency, stability or thermal
behavior on a physical A12/A15. Normal Auto remains the standard hardware path.

## Changes and regression coverage

- Publish the initialized renderer under its submission/statistics/stop lock;
  reject setup after stop rather than reviving an interrupted session.
- Sort rolling timing snapshots after releasing that lock, so diagnostics do not
  delay frame arrival or GPU completion. Timing definitions are unchanged.
- Drain the worker's temporary autorelease pool once per frame, even under a
  continuously busy producer; command-buffer completion retains the runtime
  until in-flight GPU work finishes. Physical memory-soak checks remain required.
- Recheck exact upstream revisions, tracked modifications and nested gitlinks
  even when a prepared-client cache record matches. Preserve local signing edits;
  choose a fresh destination when integration inputs change.
- Verify pending-payload release and in-flight ownership across queue stop.
- Mutate 10,000 valid coefficient-record fixtures, in addition to the existing
  10,000 random malformed frames. Every accepted complete mutation is checked
  against the real pinned CPU decoder parser and its readiness/block counts.
- Execute the actual GPU presenter: BT.601/BT.709, full/limited range,
  black/white/gray/primary colors, opaque alpha and image orientation. The 25
  offscreen cases check 3,200 pixels against independently specified reference
  colors with a two-code-value rounding tolerance. This is not display timing.
- Build unsigned Debug and Release device targets and the Debug simulator;
  run Xcode's static analyzer on the Debug device target. Keep the original
  compiler diagnostics enabled and archive complete logs/result bundles.
- Reuse FFmpeg when already installed and bound package-manager waits in CI;
  dependency-mirror stalls must not hold a test run indefinitely.

## Observed compiler warnings and fix plan

The previous [Apple5 device build](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37809452393)
used Xcode 26.6 / tvOS SDK 26.5, completed successfully, and emitted 28 warnings,
with no compiler errors. These are observed CI diagnostics; they are not a
transcription of the user's unavailable screenshots.

| Diagnostic | Meaning / importance | Action |
| --- | --- | --- |
| Three `-Wconditional-uninitialized` warnings in `ControlStream.c` | Important to inspect: a true read of an uninitialized value is unsafe. The reviewed paths assign the values inside the same `err == 0` / `invalidate` guards as their uses; no uninitialized path was demonstrated. | Explicit initialization in the staged cleanup patch, preserving the existing control flow. Confirm disappearance in Debug/Release and inspect analyzer output. |
| Four `-Wgnu-folding-constant` warnings in Wake-on-LAN/hash buffers | C/Objective-C `static const int` is not an integer constant expression for these array extents. Clang accepts an extension; buffer lengths are fixed. Low severity. | Use enum constants, with exactly the same buffer sizes and hash algorithms. |
| Two deprecated `UIActivityIndicatorViewStyleWhiteLarge` warnings | Old spinner style, no decoder effect. Low severity. | Use `UIActivityIndicatorViewStyleLarge` with explicit white color. |
| Nine ENet and one image-bitmap `-Wenum-enum-conversion` warnings | Intentional flag combinations from different enum types. No failing arithmetic demonstrated. Low severity. | Future separate patch: explicit cast to the destination flag type; verify encrypted control traffic, reconnect and box-art output. Do not disable the warning globally or change wire bits. |
| Deprecated `SecTrustGetCertificateAtIndex` | API maintenance in certificate pinning; deprecation alone does not establish a vulnerability. Medium priority because an incorrect migration could break authentication. | Migrate to `SecTrustCopyCertificateChain`, preserve exact single-certificate pin matching and ownership. Test matching/mismatched/missing/multiple certificates and pairing/reconnect before merging. |
| Two `keyWindow` deprecations | Global window lookup is ambiguous with multiple scenes. UI maintenance, low current streaming severity. | Use the controller/view's window or active scene; check loading screens, alerts and reconnect on device. |
| Deprecated button highlight/image insets | Legacy button appearance. Low severity on current UI; some properties are ignored with `UIButtonConfiguration`. | Migrate each button with equivalent focus/remote behavior and screenshots on tvOS; no blind global replacement. |
| Two launch-image deprecations | Legacy launch assets/plist; current build accepts them. No decoding effect. | Replace with a launch storyboard and remove matching asset/plist settings together; verify cold launch at 1080p/4K. |
| `libtool: win32.o has no symbols` | Platform-conditional Windows translation unit produces an empty object on Apple. Informational for this build. | Keep unless the upstream build excludes the object selectively; no runtime fix needed. |
| AppIntents metadata extraction skipped | No AppIntents dependency or intent feature is present. Informational. | No framework addition is needed to silence it. |
| GCC signedness warnings in pinned PyroWave CPU parser | Existing upstream comparisons of promoted bitfields to unsigned dimensions. No out-of-range acceptance demonstrated by interoperability/mutation tests. | Keep the pristine source pin; review an explicit-type upstream fix independently if needed. |

Xcode static-analyzer findings are separate from ordinary compiler warnings.
Inspect null dereferences, lifetime/ownership and uninitialized reads first;
confirm each path before changing protocol or authentication behavior. A successful
`analyze` command can still report findings and is not proof of runtime safety.

## Actual static-analyzer findings and prioritized work

The first review [CI run](https://github.com/JKGiova/moonlight-tvos-pyrowave/actions/runs/37892132736)
passed all five jobs, including Debug/Release device builds, the Debug simulator
and the Debug device analyzer. The device builds emitted 19 warning occurrences,
down from 28; the simulator emitted 35 because most sources build for both arm64
and x86_64. No warning/error came from the owned PyroWave runtime sources.

The analyzer additionally reported **20 findings in existing upstream code**;
its successful exit does not resolve them. They require the following work before
release qualification. The full diagnostics remain visible in the CI artifacts.

| Priority / finding | Source assessment | Concrete fix/validation plan |
| --- | --- | --- |
| P0: two apparent frees of stack `qduDS` in `VideoDepacketizer.c` | Direct-submit uses stack storage and queued-submit uses heap storage, both guarded by the global decoder capability. A callback boundary makes the analyzer suspect that capability may change. No actual invalid free was reproduced. | Reproduce direct/queued delivery and callbacks under ASan, including stop/error/overflow; verify the capability is immutable for the ownership lifetime. If a real path exists, record ownership explicitly rather than infer it from a mutable global at cleanup. |
| P0: null `pendingFecBlockList.head` in `RtpVideoQueue.c` | FEC recovery expects a nonempty pending list. The analyzer does not prove the count/head invariant through all paths. | Test empty, truncated, out-of-order and heavily lost FEC blocks; verify count/head consistency. If reachable, reject recovery before dereferencing and count the lost frame, preserving FEC cleanup. |
| P0: null `localAddress` in ENet `unix.c` | The Apple address-conversion branch checks `peerAddress`, then reads `localAddress`; the function permits optional address outputs elsewhere. The alert deserves a real API/call-site test. | Call receive with peer-only and peer+local outputs on IPv4/IPv6 dual-stack sockets. Add an explicit non-null gate for the conversion when confirmed; preserve IPv4-mapped behavior and reconnect tests. |
| P1: possible `newOpt` leak in `RtspParser.c` | The newly allocated node is passed to `insertOption`, so ownership-transfer reasoning may be incomplete. Not a demonstrated leak. | Test normal/truncated CRLF endings, malformed headers and failure cleanup under leak checking. Prove each node reaches the message/free-list owner; fix only a leaking exit path. |
| P1: nine `unix.Errno` findings in socket/control failure paths | Failure codes cross helper/callback boundaries; the analyzer cannot prove that `errno` was set. No incorrect code was measured. | Inject send/connect/get-socket-option failures; propagate an explicit error result instead of relying on stale `errno` if the helper contract does not guarantee it. Verify termination reason and retry behavior. |
| P1: three nullable UIKit arguments | Two `UIAppView` subviews are deliberately optional; the touch-removal path in `OnScreenControls` is guarded by membership but lacks a visible non-null invariant to the analyzer. | Guard absent overlays/labels before `addSubview`; reproduce with missing artwork/no running game. Validate non-null touch collection/membership, then guard removal if necessary; exercise controller/touch cancellation. |
| P2: three dead stores in ENet QoS/compression | Earlier `result` values can be overwritten by subsequent platform options; `parent` is assigned but not consumed. No stream failure demonstrated. | Review per-platform QoS result semantics before simplification; remove only redundant assignments and run transport tests. |

P0 means investigate potential crash/corruption first; it is not a claim that the
user's current stream has that bug. Preserve the pristine source pins and use
separate reviewed patches with regression fixtures. Certificate API and UI/launch
modernization from the compiler-warning table follow these ownership/transport
checks. Auto stays unqualified until these reviews and physical tests are complete.

## Reproduce and collect diagnostics

On a Mac with the same initialized source pins:

```sh
python3 tools/prepare_client.py --client-dir build/client/Moonlight-polish
python3 tools/build_tvos.py --client-dir build/client/Moonlight-polish --sdk appletvos --configuration Debug
python3 tools/build_tvos.py --client-dir build/client/Moonlight-polish --sdk appletvos --configuration Release
python3 tools/build_tvos.py --client-dir build/client/Moonlight-polish --sdk appletvsimulator --configuration Debug
python3 tools/build_tvos.py --client-dir build/client/Moonlight-polish --sdk appletvos --action analyze
```

Each invocation records a fresh `build/xcode/<configuration>-<sdk>-<action>/<run>/`
containing `xcodebuild.log`, `diagnostics.json` and `result.xcresult`. CI uploads
these as `xcode-<configuration>-<sdk>` artifacts, including failed builds.
Local logs can contain machine paths; review/redact before publishing them.
The JSON preserves warnings instead of hiding them and does not claim TV tests.

`analyze` is documented in [Apple's Xcode workflow actions](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions).
The planned certificate API replacement is [SecTrustCopyCertificateChain](https://developer.apple.com/documentation/security/sectrustcopycertificatechain(_:)).

## Required physical checks before qualification

1. On A12, use explicit PyroWave SDR and confirm the overlay actually reports
   `metal-portable-apple5`; standard streaming success is not a PyroWave test.
2. Validate saved real video against a reference, then run live start/stop,
   repeated reconnect, background/foreground and drawable-loss checks.
3. Compare native and forced portable output on A15; keep model/profile results
   separate, including both A15 variants.
4. Collect the comparable latency percentiles, queue/loss/parser/decode/present
   counters and at least 30 minutes of thermal/memory soak per admitted profile.
5. Qualify the network route and fallback behavior before enabling PyroWave Auto.

GPU encoding and a real-video native/portable comparison require a supported
encoder/device. An unavailable backend is an explicit skip, not a passing test.
No remote CI run measures the user's TV or connects to the user's paired host.
