# Build and test the initial implementation

Initialize the pinned sources:

```sh
git clone --recurse-submodules https://github.com/JKGiova/moonlight-tvos-pyrowave.git
cd moonlight-tvos-pyrowave
python3 tools/bootstrap.py
python3 tools/run_portable_tests.py
```

Portable tests need Python 3.10+ and a C++17 compiler. CMake 3.20+ is an alternative: configure the root project with `-DBUILD_METAL_VIDEO_TOOL=OFF`, build, and run CTest. The script also builds `build/portable/framing-check`; when using CMake on Windows, pass the actual validator path to `--framing-check`.

## Native Metal engine on macOS

Install Xcode command-line tools and FFmpeg/FFprobe. Run:

```sh
python3 tools/build_engine.py
python3 tools/encode_test_video.py --backend metal --roundtrip
```

The native build directly compiles the real pinned codec and does not need Granite/Vulkan. Encoding requires a GPU admitted by upstream’s native Apple7 gate (for example supported Apple Silicon Macs). The decoder-only extension now provides an experimental Apple5 path; the Intel Mac can build the tvOS app but cannot encode PyroWave with this native tool. The script generates 120 frames at 1280x720/60 of motion, gradients and text, then encodes PyroWave, H.264 and HEVC with real encoders. Outputs and logs live under ignored `benchmarks/local/video-test/`; use a fresh `--output-dir` for each run.

PyroWave invokes the native C API, packetizes and validates each frame, and writes the upstream offline `.pyrowave` file. `--roundtrip` decodes into YUV and computes PSNR against the source. It does not impose a PSNR qualification threshold or declare correctness merely from a completed decode. The offline harness deliberately waits for completion and reads pixels back; this behavior is for comparison, not the planned live renderer. GPU execution timestamps are reported only when valid; process wall time includes setup/I/O and is never labelled per-frame GPU latency.

Choose your own source/profile explicitly:

```sh
python3 tools/encode_test_video.py --backend metal --roundtrip --input video.mp4 --width 1920 --height 1080 --fps 60 --frames 120 --output-dir benchmarks/local/my-video
```

This version supports 8-bit SDR 4:2:0 only. Input shorter than the requested frame count fails; the tool does not silently loop/pad it. A pre-existing output directory is rejected to preserve evidence.

## Windows/Linux Vulkan encoder

Use a real upstream `pyrowave-encode` binary built from the pinned codec revision. Upstream development-tool builds need their own Granite/Vulkan prerequisites; the Metal tool does not provide those. This script does not download or execute an unknown encoder binary automatically.

```sh
python3 tools/encode_test_video.py --backend vulkan --encoder /path/to/pyrowave-encode --encoder-commit 186f0393b77f7755953b5ecde994bb1cec2e4155 --framing-check build/portable/framing-check
```

Its actual interface is `pyrowave-encode input.y4m output.pyrowave bytes_per_frame`. The runner validates the file/header, exact expected frame count and native Nonary framing because upstream can exit successfully even after GPU initialization fails. Declaring the revision is metadata, not a cryptographic proof; the binary SHA-256 is recorded. There is no FFmpeg PyroWave substitution. Vulkan decode/round-trip is not implemented by this runner yet.

A CPU-only functional baseline run is explicit:

```sh
python3 tools/encode_test_video.py --codecs h264,hevc --width 320 --height 180 --fps 30 --frames 12 --output-dir benchmarks/local/cpu-smoke
```

These FFmpeg CPU baselines are not Apple hardware decoder timings or matched-quality PyroWave comparisons. The default PyroWave run fails clearly when the actual encoder/GPU is unavailable.

## Integrated experimental tvOS client

On a Mac with Xcode/tvOS SDK:

```sh
python3 tools/build_tvos.py --sdk appletvos
```

This prepares selective patches and builds the actual `Moonlight TV` target without signing. Open `build/client/Moonlight/Moonlight.xcodeproj` in Xcode to configure your local team, unique persistent bundle ID and physical Apple TV deployment. Standard startup/streaming and PIN pairing come first. The standard renderer remains the fallback; the persistent PyroWave (Experimental SDR) codec preference can select the experimental live renderer. The Debug launch argument remains available for development. See [experimental client testing](experimental-client.md). Add `--baseline` to build the pristine upstream source instead. A changed integration requires a fresh `--client-dir`; existing generated checkouts are preserved.

CI builds unsigned Debug/Release tvOS device targets and the Debug simulator,
and runs the device static analyzer. Each invocation keeps complete Xcode output,
structured diagnostics and a result bundle under `build/xcode/`; CI retains
these as artifacts even on failure. Use `--action analyze` to reproduce analysis.
See [reliability and Xcode diagnostics](reliability-and-xcode.md) for the warning
review and fix plan.

CI also compiles native Metal and runs portable/smoke checks, executes the actual
portable dequantizer against known coefficient fixtures, compiles six iDWT
variants and checks the actual presenter's offscreen color/orientation output.
These tests do not qualify an Apple TV. See [Apple5 checks](apple5-decoder.md).
The Mac job probes GPU availability and performs a native encode/decode smoke
test only when supported; otherwise those steps are explicitly skipped. No CI
job measures physical TV latency or accesses the user's Vibeshine PC. See
[development status](development-status.md) and [live-test setup](vibeshine-testing.md).
