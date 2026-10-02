# Store screenshots — 1.0 (6)

Four genuine screenshots were captured October 2, 2026 from the development-signed, sandboxed Store build **1.0 (6)** at `.build/screenshot-build6/Build/Products/Debug/Face Hugger.app`. It has the same source and artwork as the uploaded release build, including the original folder-hugging icon and mascot. macOS 27, dark appearance, active window. All four replaced the build-3 set in the English (U.S.) Mac screenshot set and returned **COMPLETE**.

The app was driven with macOS UI scripting (System Events accessibility actions); windows were captured with `screencapture -x -o -l`. Text fields were filled through accessibility values, with one typed-and-deleted space per field so the app registered each edit. During capture, stray keystrokes typed on the Mac reached the app's local search field; they were cleared before any final capture. Final opaque sRGB PNGs are in [1.0-build6](1.0-build6/), framed by `Scripts/Art/frame_screenshots.swift` (centered, unscaled, 2560 × 1600 on `#25313C`; it reproduces the build-3 framing pixel for pixel). Unmodified window captures are in `1.0-build6/originals/`; checksums are in `1.0-build6/SHA256SUMS`.

| Order | File | Genuine state | App Store asset ID |
| --- | --- | --- | --- |
| 1 | `01-workspace.png` | Saved pairing applied: bookmarked fixture folder, private review repo browsed live, remote-path conflicts flagged, earlier completed upload in the shelf | `25000019-6606-8471-8009-b888409bf7e8` |
| 2 | `02-dataset-card.png` | Dataset-card editor after an actual **Draft on this Mac** run with Apple Intelligence; notes entered for the harmless fixture; draft discarded, nothing saved | `29c00019-6606-8471-8024-a7ad756fcaaa` |
| 3 | `03-file-filters.png` | Filters popover showing the saved `logs/**` exclusion; cancelled without changes | `81800019-6606-8471-8029-b307b2ec2035` |
| 4 | `04-saved-pairing.png` | Saved pairings popover | `2d000019-6606-8471-8020-2a32742d13f5` |

No upload, remote write, or file save happened during this capture. The app's saved token authenticated and listed the private review repository. Screenshot set `cdfea2a3-600d-4df0-9eff-a1cc43296baf` (`APP_DESKTOP`). No App Review submission or release was performed.

## Historical set — 1.0 (3)

The build-3 set below was replaced on October 2, 2026 because its title bars showed the retired mascot. Its files remain in [1.0-build3](1.0-build3/).

Four genuine screenshots were captured September 30, 2026 from the development-signed, sandboxed Store build **1.0 (3)** at `.build/store-xcode/Build/Products/Debug/Face Hugger.app`, using the same source and approved icon as the uploaded release build. macOS **27.0.1**, dark appearance. All four were uploaded to the English (U.S.) Mac screenshot set and returned **COMPLETE**.

Final opaque PNGs are in [1.0-build3](1.0-build3/); unmodified window captures remain in `1.0-build3/originals/`. Final size is **2560 × 1600**. Captures were centered at their original pixel size on a solid slate background; no scaling, reconstructed UI, fabricated counters, or painted-over content. Native `screencapture -x -o -l` was used after the user explicitly authorized that capture method. Native Screenshot/Preview export attempts had failed; CUA was used for all app interactions.

| Order | File | Genuine state | App Store asset ID |
| --- | --- | --- | --- |
| 1 | `01-prepared-workspace.png` | Four included files, one excluded log, selected destination | `9cc00019-6606-8471-800d-24333e3dbde0` |
| 2 | `02-file-filters.png` | Applied `logs/**` exclusion shown in popover | `0d400019-6606-8471-802e-4dbae70bd926` |
| 3 | `03-upload-complete.png` | Real 508-byte, four-file upload completed; remote files visible | `6c000019-6606-8471-8026-b512f5d22ac8` |
| 4 | `04-saved-pairing.png` | Actual saved source/destination pairing | `8ac00019-6606-8471-8019-841d4df42f50` |

App `6817866865`, version ID `6302c414-5900-40dd-bb0d-2b886d65496b`, localization `7ce2b112-74b6-458e-8d2c-2d34f08fce38`, screenshot set `cdfea2a3-600d-4df0-9eff-a1cc43296baf` (`APP_DESKTOP`). No App Review submission or release was performed.

## Fixture and retained review state

Harmless demonstration files live under `.build/store-screenshot-fixture/Dataset Preview`: README, dataset metadata, two tiny JSONL files, and an excluded preparation log. The four included files were actually uploaded to `reviewer-test/` in the authorized private review dataset `zakkeown/face-hugger-app-review-89503494`. The repository root README was not changed. These sample files, the local fixture, completed history entry, and saved pairing are intentionally retained for review/reproduction; they are not production data. The review repository and restricted token remain available. Credentials were transferred by native clipboard, never included in images, and replaced on the clipboard afterward.

Apple accepts Mac screenshots at 1280×800, 1440×900, 2560×1600, or 2880×1800; see [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/). CLI validation and pixel inspection passed. The sample upload was too small to support a useful in-progress capture, so no staged or invented progress/stopped state was added.

Earlier direct-beta inspection notes in [direct-beta-previews](direct-beta-previews/README.md) are historical only and were not submitted.
