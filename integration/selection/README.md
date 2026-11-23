# Codec selection integration

Manual **PyroWave (SDR)** checks host capability, GPU/profile admission and exact
RTSP bitstream identity. The renderer follows the negotiated format.
**Preferred Codec → Auto** retains standard Moonlight selection.
**Bitrate → Auto (by stream profile)** is implemented independently.

There is no benchmark-aware codec selector or automatic session retry.
[Current behavior](../../docs/codec-selection.md)
