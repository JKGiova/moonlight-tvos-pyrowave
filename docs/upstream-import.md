# Future upstream import

Status: deferred until implementation is authorized.

This repository starts as an independent planning scaffold. It is not yet a GitHub fork and contains no upstream app source or registered submodules.

When implementation starts:
1. Import the pinned Moonlight iOS/tvOS baseline with history or a clearly recorded source snapshot; preserve LICENSE.txt and original copyrights.
2. Put the app and Xcode project at their standard upstream paths. Do not create a parallel fake src/ app tree.
3. Retain the common-c baseline and transfer reviewed Nonary video/protocol patches onto a dedicated fork, preserving upstream fixes.
4. Add PyroWave Metal at a fixed commit under an appropriate dependency directory, with its MIT license and patch ledger.
5. Register genuine submodules/gitlinks only after the dependency layout and references exist; the current JSON manifest is not a git submodule lock.
6. Build unmodified baseline on the physical device before changing the decoder.
7. Enable macOS app-build CI only once a real Xcode target exists.

Do not copy the Nonary Qt application to tvOS. Do not copy Android wire parsing without verifying the Nonary container.
