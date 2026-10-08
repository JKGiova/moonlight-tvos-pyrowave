# Planned integration boundaries

The subfolders contain boundary notes. Actual app/common-c and Metal changes are reviewable patches under `patches/`, applied to generated copies by `tools/prepare_client.py` and `tools/prepare_metal.py`.

- tvos/: standard app integration
- metal/: native and portable PyroWave Metal paths for the full device matrix
- protocol/: Nonary interoperability
- selection/: client Auto/manual decision policy

The pristine app remains pinned at upstream-compatible paths in `app/Moonlight`, as described in [upstream import](../docs/upstream-import.md). The live renderer and portable Apple5 shader are in `native/apple`.

- network/: five-second host RTT and throughput monitoring, bounded capacity qualification
