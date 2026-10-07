# Metal integration boundary

Planned changes: pinned PyroWave native Metal dependency, portable Apple5 dequantization for A12, native Apple7-or-later candidate for A15, offline harness, texture pool and GPU presentation. Select the backend through actual capability and pipeline checks; qualify correctness and latency on physical devices per model/backend/profile. No model is qualified yet. See [device support](../../docs/device-support.md) and [decode performance](../../docs/decoding-performance.md).
