# Project instructions

## Authorized phase

This repository is a planning scaffold. Do not implement decoder, renderer, selector, application targets or source imports until the user authorizes development. Documentation, directory structure, manifests and templates are in scope.

## Engineering rules for the implementation phase

- Read README.md, docs/PLAN.md, docs/decoding-performance.md and docs/codec-selection.md first.
- Optimize client decode latency without silently lowering resolution, frame rate, bit depth or requested color profile.
- Benchmark the physical device. Simulator or desktop measurements are not Apple TV results.
- Never mark an unmeasured backend supported or publish synthetic results as measurements.
- Maintain separate counters for network loss, parser rejection, decode overload and present drops.
- Auto prefers PyroWave only when admission gates pass; never force it on an unsupported device.
- Treat codec selection, host encoding and client decoding as distinct responsibilities.
- Preserve upstream fixes and licenses. Do not blindly replace moonlight-common-c with a diverged fork.
- Keep queues bounded and record p50/p95/p99 latency plus steady-state throughput.
- Public documentation and fixtures must exclude host addresses, pairing material and credentials.
