# Face Hugger design direction

**Transfer Bench is the selected design target.** The approved state pass covers an empty workspace, stopped/interrupted uploads, dark mode, and saved pairings in a toolbar popover. These are interactive design prototypes; the current SwiftUI app still uses the earlier sidebar, queue, inspector, and upload sheet. That composition is historical implementation context, not the intended direction.

See the [interactive Transfer Bench prototype](https://p.superdesign.dev/draft/3f6d6851-b4e3-4d68-a1bf-f8a378ccad65), [redesign rationale and implementation implications](redesign.md), and [design canvas](https://superdesign.dev/teams/d6bf7272-b808-4594-89cb-9ed77f64920c/projects/016e36f9-f366-4c98-836f-c9bbf5783746).

## Composition and workflow

Two aligned file surfaces connect **On this Mac** to **On Hugging Face**. A small gold directional element joins their headers; a continuous slate activity shelf anchors both panes. No permanent sidebar, card grid, or separate inspector. Keep the approved mascot at a small identity scale rather than above an empty-state slogan.

Drop or choose a folder to stage its contents in place. A searchable repository selector updates the remote pane. Filters open on demand. A concise review strip identifies the destination, visibility, and matching remote paths before an explicit Upload action. Matching paths indicate potential replacement, not content equality. Starting a transfer moves its activity into the shelf while browsing remains available.

Saved pairings live in a compact toolbar popover. Choosing one restores both endpoints and filters, never starts a transfer, and must not silently discard unsent work. History and logs belong with the activity shelf. Pairings do not imply automatic synchronization.

## Visual system

Use contiguous native surfaces, aligned columns, semantic controls, visible keyboard focus, and resizable panes. At the 1240 × 820 reference size, file rows are 31–32 pt with 24 pt pane padding. SF Pro folder/repo titles are 24–28 pt, section titles 15–16 pt, rows and controls 13–14 pt, and metadata at least 12 pt. Use monospaced digits for counters; reserve SF Mono for raw logs.

| Role | Light | Dark |
| --- | --- | --- |
| Local surface | Porcelain `#F5F3EE` | Warm graphite `#292B2C` |
| Remote surface | Cloud `#F8FAFC` | Blue graphite `#252D35` |
| Activity shelf | Slate `#253443` | Recessed slate `#1C252E` |
| Primary text | Ink `#253443` | `#EDF0F2` |
| Secondary text | `#64707C` | `#ADB7C0` |
| Direction / primary action | Gold `#F6C845`, ink text | Same |

Gold marks direction and the primary action, not every selection. Dark mode preserves the same geometry and hierarchy. Success and failure always include text or an icon. Respect Reduce Motion; no ambient mascot animation is needed.

## Approved state pass

- **Empty:** retain the paired workspace and useful remote browsing. Offer Choose folder and a modest drop affordance; disable Upload until ready. Collapse an empty activity shelf to about 64 pt.
- **Running:** show reported preparation, upload/reuse, and committed counts as concurrent activity. Never invent an overall percentage, speed, or ETA, or imply a sequential wizard.
- **Stopped this session:** preserve the route and explicitly label available counters as last reported. Show Resume upload and explain that already committed files remain remote and the source is checked again.
- **Recovered after relaunch:** show only persisted state. Do not invent retained counters, logs, or a cause. If the source is unavailable, help locate it before resuming.
- **Prototype controls:** state selector and appearance toggle sit outside the app frame; sample data is illustrative and actions never touch a real account.

## Assets

`Resources/Assets.xcassets` contains the app icon in all standard Mac sizes and a transparent `Hugger` image. The user explicitly directed the identity toward a Hugging Face-like emoji wrapped by an Alien-style facehugger. The artwork has a happy yellow face, hugging hands, tan segmented fingers around the head, and a long curved tail. No folder, upload glyph, or antenna blob remains.

The master artwork is `Resources/Artwork/face-hugger-master.png`, generated with the built-in imagegen tool. `Scripts/Art/build_assets.swift` mechanically resizes it, preserving transparency, and packages the icon on a pale native rounded tile. Run `swift Scripts/Art/build_assets.swift` to regenerate all sizes. Generation prompt is recorded in `Resources/Artwork/prompt.txt`.
