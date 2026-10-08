# Upstream import and layout

Implementation was authorized on 2026-10-07. The standard app is registered as a genuine submodule at `app/Moonlight`, pinned to `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`. Its actual `Moonlight.xcodeproj`, `Limelight`, `Moonlight TV`, bundled libraries and license remain at their original relative paths. The PyroWave source is a submodule at `third_party/pyrowave`, pinned to `186f0393b77f7755953b5ecde994bb1cec2e4155`.

`python3 tools/bootstrap.py` initializes and verifies both sources and nested dependencies, including the standard common-c baseline. No Nonary common-c replacement was made. Build unmodified Moonlight on the device before qualifying changes.

Future app modifications must be committed to a reviewed app-source branch/fork or maintained as reviewed patches applied to the pinned working tree, then referenced explicitly. Do not rely on uncommitted submodule changes. Transfer Nonary protocol fixes selectively, retaining the standard baseline’s corrections and licenses.

The native Metal offline tool and prepared client use a generated dependency copy plus the reviewed Apple5 decoder patch. Encoding preserves the original Apple7 gate; the decoder-only factory selects portable Apple5 or native Apple7 after capability/pipeline checks. See [Apple5 implementation](apple5-decoder.md); physical validation remains pending. The portable Nonary framing adapter records its source and modifications in [UPSTREAM.md](../native/protocol/UPSTREAM.md).

No Qt application or incompatible Android container is imported. See [build and test](build-and-test.md).
