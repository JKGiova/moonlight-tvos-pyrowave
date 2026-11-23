# tvOS app integration

The genuine Moonlight app remains pinned under `app/Moonlight`.
`tools/prepare_client.py` creates the integrated Xcode project from selective
patches without modifying the source submodule.

Implemented: manual PyroWave SDR admission, negotiated-format renderer dispatch,
persistent codec/bitrate settings, a PyroWave frame-wait worker and statistics
overlay. Standard codec paths, PIN pairing and the standard PC/app UI are retained.
The app uses native Metal with portable Apple5 and native Apple7-or-later decoder
candidates. [Apple TV guide](../../docs/experimental-client.md)

The reference dashboard patch is excluded from standard preparation. No Debug
auto-connect or benchmark-aware codec Auto implementation is present.
