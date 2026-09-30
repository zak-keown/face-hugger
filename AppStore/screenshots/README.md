# Screenshot plan — pending the final Store build

No screenshots have been uploaded. The current 0.1.0 direct-distribution beta is not the self-contained, sandboxed Store build. Screenshots inspected from that beta are provisional UI evidence only; they must not be submitted as final Store screenshots.

## Format

Apple currently accepts Mac screenshots at **1280 × 800, 1440 × 900, 2560 × 1600, or 2880 × 1800**, all 16:10. Use **2880 × 1800 PNG** as the consistent final capture target, provided the native UI can be captured at that size without stretching. These dimensions are from [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), checked September 30, 2026.

A listing accepts one to ten screenshots in PNG or JPEG formats. Five strong product views are sufficient for this plan; an app-preview video is optional and is not planned for the first submission. See [Apple's upload guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).

Capture the native app at the intended window geometry and verify output pixel dimensions. Do not stretch a different aspect ratio or reconstruct controls in a design tool. Use the same scale and appearance within a sequence. Do not infer final screenshots from the Superdesign prototype.

## Proposed sequence

| Order | Suggested filename | Actual state to capture | What it demonstrates |
| --- | --- | --- | --- |
| 1 | `01-transfer-bench-light.png` | A prepared local folder and a selected private repository, with real filenames, sizes, and destination visible | Review source and destination together |
| 2 | `02-file-filters-light.png` | Filters popover over that workspace; real glob patterns and staged included/excluded files | Choose which files to upload |
| 3 | `03-upload-activity-dark.png` | An actual bounded transfer in progress, with reported preparation/upload/commit counts | Understand ongoing upload activity |
| 4 | `04-stopped-upload-dark.png` | The same transfer deliberately stopped through the app; last-reported values and Resume action | Stop and resume without pretending to show a live transfer |
| 5 | `05-saved-pairings-light.png` | Actual saved pairings in the popover, with recognizable source and repository names | Reuse destinations without automatic synchronization |

A sixth screenshot of real remote folder browsing is optional if it communicates a capability that the first view does not. The empty workspace is useful QA evidence, but should not lead the Store sequence: it does not show the product doing work.

## Capture preparation

Use a dedicated, authorized demonstration repository and harmless local fixture files. The files must actually exist and their displayed measurements must come from the app. Clearly distinguish such sample content in the capture record; do not fabricate job counters, a throughput figure, or a completed transfer. Never expose tokens, private user files, or account setup screens containing credentials. No live upload or creation of a demonstration repository was performed during this screenshot-planning pass.

Before capturing final shots, verify the Store build version matches the listing, its runtime/setup flow is final, and the actual sandboxed source-folder access works. A real store build must provide the demonstrated behavior; a notarized direct beta is a separate artifact. Branding and rights decisions remain with the release owner, as recorded in [the listing handoff](../README.md).

For each file, record build version/number, build identity, macOS version, appearance, pixel dimensions, capture time, fixture/repository purpose, and whether any external caption treatment was applied. If captions are later added, keep them outside the captured app and keep an untouched source image. No screenshot imagery should be regenerated or painted over.

## Current inspection

See [direct-beta preview notes](direct-beta-previews/README.md). Two actual CUA screenshots were rendered and inspected inline: the dark empty workspace and the Filters popover. No PNG was successfully exported to this directory. The available CUA screenshot API exposed inline output but no documented file-save operation; a native screenshot workflow was unsuccessful. Do not treat these notes as completed screenshot assets.

Final capture, pixel validation, review, and upload are all still pending. Keep provisional captures under `direct-beta-previews/`; put approved final Store images in a separate versioned directory only after the Store build exists.

## Store 1.0 (2) capture attempt

The actual development-signed Store build opened successfully at `.build/store-xcode/Build/Products/Debug/Face Hugger.app`. Native Screenshot failed to launch (Cocoa/launchd error); Preview → File → Take Screenshot → From Window returned to the Open dialog. No PNG was exported or uploaded. Manual fallback: prepare the actual workspace, press Shift–Command–5, capture the selected app window, save PNG, then verify supported pixel dimensions before upload. Keep account/token settings closed. The UI inspection showed the empty Transfer Bench; this is not a completed marketing shot.
