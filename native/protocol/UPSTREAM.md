# Protocol source provenance

`pyrowaveframing.cpp` and `.h` adapt Nonary/moonlight-qt revision `1ad5848bd2190ab9dd9eea00d4730740d530ec29`, paths `app/streaming/video/pyrowave/pyrowaveframing.*`. The original project uses GPL-3.0-or-later; the code retains that license. COPYING is the GPL v3 text retained from the standard Moonlight source. Original comments and namespace are preserved.

Local changes: negotiated-geometry and 64 MiB frame bounds; overflow-safe packet maps; critical-count bounds; no leading padding; sequence/order validation in length-prefixed frames; duplicate-block rejection; reusable block-seen storage; bounded control/magnitude/sign-region validation before GPU consumption; quantization-exponent range checks. Valid framing and bitstream identity remain unchanged. Full semantic shader/color correctness requires GPU/device tests.

`pyrowave_file.hpp` is original MIT material describing the upstream offline `PYROWAVE` file header and frame lengths. This is an offline harness container, not GameStream/RTP framing and not the Android PYRW container. Combined programs linking the GPL parser must retain the applicable GPL obligations.

Tests exercise the actual pinned PyroWave CPU BlockLayout, packetizer and BitstreamParser, separately from Metal GPU tests. No synthetic unit fixture is recorded as encoded video or a GPU benchmark.
