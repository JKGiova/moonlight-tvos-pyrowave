# Third-party source policy

Registered submodules: app/Moonlight at 02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a and third_party/pyrowave at 186f0393b77f7755953b5ecde994bb1cec2e4155. Their licenses remain in their original trees. Native protocol code adapts the pinned Nonary parser, with its GPL copy and provenance ledger.

Moonlight and protocol-source imports must retain their original GPL license and copyrights. PyroWave must retain its MIT license and attribution. The source manifest records reviewed pins. See native/protocol/UPSTREAM.md for the imported parser and local modifications; the original scaffold MIT license does not relicense upstream code.

Record every imported commit, local patch, bitstream identity and relevant API/ABI change. Do not include desktop-only Granite/Vulkan dependencies merely because the Qt client uses them: the planned Apple backend is native Metal.
