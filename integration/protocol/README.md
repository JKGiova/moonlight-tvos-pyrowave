# Protocol boundary

Planned changes: selective Nonary common-c video/RTSP patches, matching bitstream identity, record/length-prefixed parser and loss metadata. Android PYRW framing is not assumed compatible. No protocol code has been imported.

Implemented foundation: native/protocol/pyrowaveframing.* validates Nonary frames and is used by the offline decode harness. App common-c dispatch/negotiation remains pending; the baseline common-c dependency was not replaced.
