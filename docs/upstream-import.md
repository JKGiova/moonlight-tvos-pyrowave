# Upstream import and layout

Implementation was authorized on 2026-10-07. The standard app is registered as a genuine submodule at `app/Moonlight`, pinned to `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`. Its actual `Moonlight.xcodeproj`, `Limelight`, `Moonlight TV`, bundled libraries and license remain at their original relative paths. The PyroWave source is a submodule at `third_party/pyrowave`, pinned to `186f0393b77f7755953b5ecde994bb1cec2e4155`.

`python3 tools/bootstrap.py` initializes and verifies both sources and nested dependencies, including the standard common-c baseline. No Nonary common-c replacement was made. Build unmodified Moonlight on the device before qualifying changes.

Future app modifications must be committed to a reviewed app-source branch/fork or maintained as reviewed patches applied to the pinned working tree, then referenced explicitly. Do not rely on uncommitted submodule changes. Transfer Nonary protocol fixes selectively, retaining the standard baseline’s corrections and licenses.

The native Metal offline tool uses the original dependency and preserves its Apple7 device gate. Apple5 adaptation remains a separate shader/library change that requires correctness and physical validation. The portable Nonary framing adapter records its source and modifications in [UPSTREAM.md](../native/protocol/UPSTREAM.md).

No Qt application or incompatible Android container is imported. See [build and test](build-and-test.md).
