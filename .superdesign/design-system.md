# Face Hugger

Native macOS SwiftUI utility for moving folders to Hugging Face, now undergoing a deliberate product redesign. The prior generic sidebar/queue/inspector composition was rejected by the user. Source code is functional context, not a visual template to preserve.

## Identity

Preserve the approved glossy smiling yellow emoji wrapped by a tan Alien-style facehugger. Exact Brand Asset: Resources-Assets.xcassets-Hugger.imageset-hugger.png. Use the supplied image, never substitute an emoji, new mark, or invented drawing. Give it an intentional small home at the junction of local and remote work; do not center it above a slogan in a blank screen.

## Selected direction: Transfer Bench

The product should visibly connect a folder on this Mac to a repository on Hugging Face. Native direct manipulation, a readable file surface, a searchable destination selector, and persistent upload activity replace a long upload form. Saved source/destination pairings are a proposed improvement for repeat work, not existing functionality. No automatic sync or deletion implied.

Palette: source porcelain #F5F3EE, remote cloud #F8FAFC, ink/slate #253443, butter gold #F6C845, transfer blue #3689BE, secondary text #64707C. Primary action uses dark text on gold. Restrained success green and error red always have text. A deep slate activity shelf can anchor the window; no neon, gradients, decorative charts, dashboard card grids, or fake terminal styling.

Dark appearance: warm graphite source #292B2C, blue graphite remote #252D35, titlebar #303438, recessed dock #1C252E, primary text #EDF0F2, secondary #ADB7C0, dividers #43505B. Retain gold #F6C845 with ink text, use readable activity blue #86C6EE and success #8BD5A3. Differentiate surfaces through small luminance/temperature changes, not glowing edges. Keep the exact same geometry and hierarchy as light mode.

## State refinement

First upload retains the paired workspace. Local side has a real Choose folder action and drop affordance; connected remote destination stays useful. The activity shelf collapses to a quiet 64 pt when empty. No giant mascot, slogan, or empty dark slab. Saved pairings live in a toolbar popover and can restore a source, repo, subfolder and filters; no permanent pairing rail or implied automatic sync.

An interrupted upload remains visible in the shelf with a plain Stopped label, last-reported counts explicitly labeled as such, and Resume upload as the clear action. Do not invent retained counters after app relaunch; only show persisted state where applicable. Explain that committed files remain remote and resuming checks the source again. Preserve surrounding browsing context. An example manually stopped transfer is not a fake network diagnosis.

Interactive concept previews may have a clearly separated preview-only state selector outside the application frame and an appearance toggle. Changing samples must not mutate any real file or account. Label sample data as illustrative outside the window, and keep this preview scaffolding out of the production design.

SF Pro system typography: 24–28 pt folder/repo names, 15–16 pt section titles, 13–14 pt readable file rows and controls, 12 pt metadata floor. SF Mono only for raw logs, not headings or labels. Align file columns carefully. 8/12/16/24/32 spacing; avoid excess padding that forces scrolling in ordinary windows. Native window controls, menus, focus, resizable panes and keyboard behavior remain.

One memorable structural move per concept. Full contiguous work surfaces, hierarchy through material and placement rather than a border around everything. Warm character and serious file handling should coexist. Empty states show where to put a folder and choose a destination within the same useful workspace.

## Truthful behavior

Preparation, upload/reuse and commits overlap; never imply a sequential three-step wizard or invented overall percentage, speed or ETA. Show reported stage counts. Stop and Resume are accurate; do not promise pause. Local staging previews, saved pairings, and matching-path summaries are proposals requiring implementation. Show only feasible metadata in concepts and identify mock data as illustrative in presentation. Remote visibility must remain obvious before upload. Remote replacement affects matching paths, not unrelated files. Logs are an optional drawer. Mac may keep working after its window closes.

Design application windows at 1240×820, not landing pages. Realistic modest fixtures: rena-checkpoint, tokenizer.json, config.json, model-00001-of-00004.safetensors, owner/rena-7b. Avoid multi-terabyte examples.
