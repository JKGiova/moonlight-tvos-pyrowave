# Protocol integration

Implemented: Nonary framing validation and selective complete-frame common-c
negotiation/SDP/depacketizer patches. Strict bitstream identity is checked before
PyroWave negotiation. The original common-c baseline is retained.

Incomplete frames follow baseline loss handling; the live adapter does not deliver
partial-frame loss/record-start metadata or critical-packet sideband to the decoder.
Controller haptics and unrelated donor changes are not imported. Android PYRW
framing is a different container. See [transport boundaries](../../docs/experimental-client.md#current-transport-boundary)
and [GPL provenance](../../native/protocol/UPSTREAM.md).
