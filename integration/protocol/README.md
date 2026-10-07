# Protocol boundary

Implemented: Nonary framing validation and selective complete-frame common-c negotiation/SDP/depacketizer patches. Strict bitstream identity is required before PyroWave selection. The pristine baseline is retained; controller haptics and unrelated donor changes are not imported.

Loss metadata, record-start flags, critical-packet delivery, partial recovery and reassembly deadlines remain pending. Current incomplete frames follow stock loss handling. Android PYRW framing is not assumed compatible. See [experimental client testing](../../docs/experimental-client.md) and the GPL provenance in native/protocol/UPSTREAM.md.
