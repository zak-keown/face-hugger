# Face Hugger design direction

Face Hugger is a Mac workbench for moving large local folders into Hugging Face repositories. Its character is the Face Hugger pun: a smiling Hugging Face-style yellow emoji wrapped by a tan Alien-style facehugger, rendered like a glossy emoji and never scary. The interface should feel as dependable as Finder and as clear as a well-designed transfer utility.

## Palette and typography

- System window and sidebar materials form the base; honor light and dark appearance.
- Hugger yellow `#FFD24B` identifies the brand, primarily in artwork and selection accents.
- Action amber `#B76B00` is suitable for small accent text on light backgrounds.
- Transfer blue `#3699E3` belongs to upload activity; tan in the artwork belongs to the facehugger.
- Ink `#29313B` is used in the light artwork; application text uses semantic primary/secondary styles.
- Success uses the system green; failures use system red with a descriptive label, never color alone.

Use SF Pro via the system font throughout. Window titles are 22–26 pt semibold, job names 13–14 pt semibold, body and controls 13 pt, metadata 11–12 pt. Monospaced digits help transfer values remain steady; reserve full monospaced text for paths and raw logs. Avoid large dashboard numbers, status cards, or uppercase micro-labels.

## Layout

Use a 210–240 pt translucent sidebar, a flexible central list, and an optional 290–320 pt inspector. The toolbar carries navigation and New Upload. Align content left; center only the initial empty state. Use native separators, list selection, disclosure controls, and keyboard focus.

```
┌─────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Face Hugger                         [New Upload] [Inspector] │
├───────────────────┬─────────────────────────────┬───────────────────┤
│ Uploads           │ Uploads                     │ Selected upload   │
│ History           │                             │ Source            │
│                   │ Folder name      Uploading  │ Destination       │
│ Repositories      │ owner/repo                  │                   │
│   owner/repo      │ ━━━━━━━━━────────────       │ Prepare ✓         │
│                   │ Uploading files             │ Upload  …         │
│                   │                             │ Commit  ○         │
│                   │ Next folder          Queued │                   │
│ Account           │                             │ Show log          │
└───────────────────┴─────────────────────────────┴───────────────────┘
```

Rows show source name, destination, state, and an honest progress signal. Never show an invented percentage, speed, or ETA when the CLI has not reported one. Use an indeterminate progress view plus the latest useful activity text. Committing is distinct from transferring.

The empty state uses the transparent Hugger image at about 140 pt, the title **A little help with big uploads**, one sentence, and **New Upload**. No extra decorative cards or fake statistics. Keep the mascot out of operational rows.

## Interaction and voice

Call actions New Upload, Resume, Stop, Open on Hugging Face, and Reveal in Finder consistently. Show full destination and public/private visibility before starting a transfer. Interrupted jobs remain visible after relaunch. Destructive remote actions need a concrete file list and repository identity in the confirmation.

No ambient mascot animation is needed for the first version. Native progress indicators provide enough motion; respect Reduce Motion. Use standard materials and semantic colors to inherit future macOS refinements.

## Assets

`Resources/Assets.xcassets` contains the app icon in all standard Mac sizes and a transparent `Hugger` image. The user explicitly directed the identity toward a Hugging Face-like emoji wrapped by an Alien-style facehugger. The artwork has a happy yellow face, hugging hands, tan segmented fingers around the head, and a long curved tail. No folder, upload glyph, or antenna blob remains.

The master artwork is `Resources/Artwork/face-hugger-master.png`, generated with the built-in imagegen tool. `Scripts/Art/build_assets.swift` mechanically resizes it, preserving transparency, and packages the icon on a pale native rounded tile. Run `swift Scripts/Art/build_assets.swift` to regenerate all sizes. Generation prompt is recorded in `Resources/Artwork/prompt.txt`.
