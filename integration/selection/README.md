# Codec selection integration

Manual **PyroWave 4:2:0 / 4:4:4** checks host capability, GPU/profile admission and exact
RTSP bitstream identity. The renderer follows the negotiated format.
**Preferred Codec → Auto** retains standard Moonlight selection.
**Bitrate → Auto (by stream profile)** is implemented independently.

There is no benchmark-aware codec selector or automatic session retry.
[Current behavior](../../docs/codec-selection.md)

HDR and explicit 4:4:4 require the exact requested profile; unsupported requests fail instead of silently downgrading. See [color profiles](../../docs/video-profiles.md).
