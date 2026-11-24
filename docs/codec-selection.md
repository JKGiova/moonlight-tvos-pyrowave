# Current codec selection

The host encodes; the Apple TV negotiates a format and binds its renderer to the
format actually selected. The persistent **PyroWave 4:2:0 / 4:4:4** setting is available
in Debug and Release.

| Preferred Codec | Current behavior |
| --- | --- |
| Auto | Standard Moonlight hardware-codec negotiation; no automatic PyroWave choice |
| PyroWave 4:2:0 | Explicit 8-bit 4:2:0, or 10-bit 4:2:0 with HDR enabled |
| PyroWave 4:4:4 | Explicit 8-bit 4:4:4, or 10-bit 4:4:4 with HDR enabled |
| Standard codec choices | Retain Moonlight's existing negotiation and support checks |

The manual PyroWave path checks host capability and renderer backend admission.
The RTSP response must contain exactly one matching
`a=x-ss-pyrowave.bitstream:186f0393` attribute. A missing, duplicated or mismatched
identity preserves standard negotiation for the original SDR 4:2:0 request.
An explicit HDR or 4:4:4 request requires the exact selected PyroWave format;
missing host/profile support, identity mismatch or resource initialization failure
rejects the session instead of reducing bit depth or chroma. The overlay reports
the actual result. [Color profiles and HDR10+ status](video-profiles.md)

A decoder or shader startup failure after PyroWave negotiation rejects the
session. There is no automatic reconnect with another codec. Select Auto or HEVC
for the next manual launch.

## Backend choice

The decoder-only factory selects `metal-portable-apple5` for Apple5/6 devices and
`metal-native-apple7` for Apple7-or-later candidates after pipeline/resource checks.
This is capability admission, not a physical-device performance certificate.
[Backend implementation](apple5-decoder.md)

## Debug arguments

- `-PyroWaveExperimental YES` requests PyroWave when Preferred Codec is Auto.
  Release builds ignore this argument.
- `-PyroWavePortable YES` forces the portable decoder for a Debug experiment on a
  capable device when PyroWave is requested.

## Bitrate Auto is independent

**Auto (by stream profile)** in the Bitrate menu computes the initial bitrate
request after codec negotiation. It does not select a codec, calibrate a network
route or qualify PyroWave. [Profile values](experimental-client.md#bitrate-and-comparison-runs)

`configs/codec-policy.example.json` is design reference data; the app does not load
it. No benchmark-aware ranking, qualification cache, cooldown or automatic session
retry is implemented.
