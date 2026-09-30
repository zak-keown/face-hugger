# Face Hugger design direction

**Transfer Bench is implemented in the native SwiftUI app.** It replaces the earlier sidebar, queue, inspector, and upload-sheet main workflow with paired file surfaces, local staging, and an activity shelf. The approved interactive prototype remains a design reference; its sample files and preview-only controls are not app functionality. Native build success does not by itself establish visual or end-to-end verification.

See the [interactive Transfer Bench prototype](https://p.superdesign.dev/draft/3f6d6851-b4e3-4d68-a1bf-f8a378ccad65), [redesign rationale and implementation implications](redesign.md), and [design canvas](https://superdesign.dev/teams/d6bf7272-b808-4594-89cb-9ed77f64920c/projects/016e36f9-f366-4c98-836f-c9bbf5783746).

## Composition and workflow

Two aligned file surfaces connect **On this Mac** to **On Hugging Face**. A small gold directional element joins their headers; a continuous slate activity shelf anchors both panes. No permanent sidebar, card grid, or separate inspector. Keep the approved mascot at a small identity scale rather than above an empty-state slogan.

Drop or choose a folder to stage its contents in place. A searchable repository selector updates the remote pane. Filters open on demand. The repository header identifies visibility; a review strip shows measured file totals, destination-folder controls, and a general matching-path replacement warning before an explicit Upload action. Per-file status compares exact remote paths; it detects file/folder conflicts but does not compare contents. Starting a transfer moves its activity into the shelf while browsing remains available.

Saved pairings live in a compact toolbar popover. Choosing one restores both endpoints and filters, never starts a transfer, and must not silently discard unsent work. History and logs belong with the activity shelf. Pairings do not imply automatic synchronization.

## Visual system

The app uses contiguous native surfaces, file tables, and semantic controls. The two panes share the available width; there is no user-draggable splitter. The 1240 × 820 prototype establishes the alignment target: 31–32 pt rows, 24 pt pane padding, and aligned 136 pt headers. SF Pro folder/repo titles are 25 pt, section titles 15–16 pt, rows and controls 13–14 pt, and metadata 12 pt. Use monospaced digits for counters; reserve SF Mono for raw logs.

| Role | Light | Dark |
| --- | --- | --- |
| Local surface | Porcelain `#F5F3EE` | Warm graphite `#292B2C` |
| Remote surface | Cloud `#F8FAFC` | Blue graphite `#252D35` |
| Activity shelf | Slate `#253443` | Recessed slate `#1C252E` |
| Primary text | Ink `#253443` | `#EDF0F2` |
| Secondary text | `#64707C` | `#ADB7C0` |
| Direction / primary action | Gold `#F6C845`, ink text | Same |

The table records the shared adaptive theme. The current activity shelf uses its own fixed dark slate colors in both appearances. Gold marks direction and primary actions. Dark mode preserves the same geometry and hierarchy. Success and failure always include text or an icon. Respect Reduce Motion; no ambient mascot animation is needed.

## Native states and remaining polish

- **Empty:** retain the paired workspace and useful remote browsing. Offer Choose folder and a modest drop affordance; disable Upload until ready. Collapse an empty activity shelf to about 64 pt.
- **Running:** show reported preparation, upload/reuse, and committed counts as concurrent activity. Never invent an overall percentage, speed, or ETA, or imply a sequential wizard.
- **Stopped this session:** preserve the route and explicitly label available counters as last reported. Show Resume upload and explain that already committed files remain remote and the source is checked again.
- **Recovered after relaunch:** show only persisted state. Do not invent retained counters, logs, or a cause. An unavailable source produces a validation failure on resume and offers Locate folder without automatically restarting.
- **Saved pairings:** the toolbar popover saves, restores, and removes named source/destination/filter configurations; applying a pairing over a prepared source asks for confirmation. Pairing search, rename, and active-pairing indication are not implemented.
- **Prototype controls:** the reference prototype has an external state selector and appearance toggle. The native app follows system appearance and operates on real files/accounts; it has no sample-state switcher.

## Assets

`Resources/Assets.xcassets` contains the app icon in all standard Mac sizes and a transparent `Hugger` image. The user explicitly directed the identity toward a Hugging Face-like emoji wrapped by an Alien-style facehugger. The artwork has a happy yellow face, hugging hands, tan segmented fingers around the head, and a long curved tail. No folder, upload glyph, or antenna blob remains.

The master artwork is `Resources/Artwork/face-hugger-master.png`, generated with the built-in imagegen tool. `Scripts/Art/build_assets.swift` mechanically resizes it, preserving transparency, and packages the icon on a pale native rounded tile. Run `swift Scripts/Art/build_assets.swift` to regenerate all sizes. Generation prompt is recorded in `Resources/Artwork/prompt.txt`.

File-status follow-up: the native local table now shows New path, Remote path exists, Excluded, or Not checked. This compares previewed paths only, without content-equality claims. Missing-source jobs support Locate folder and manual resume; likely account/network failures show recovery guidance.
