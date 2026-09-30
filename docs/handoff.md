# Face Hugger handoff — September 30, 2026

## Current outcome

Native macOS Transfer Bench design is preserved. The owner requested a more cartoon-like creature and nonwhite icon background; the revised smooth emoji artwork is in Resources/Artwork/face-hugger-icon-v2.png, with mechanical icon-size packaging in Scripts/Art/build_assets.swift. Build 3 packages this icon and the supplemental LibYAML notice; build 2 remains attached until replacement upload completes. Store variant **1.0 (2)** now has a self-contained universal upload runtime, App Sandbox, persistent folder bookmarks, nested signatures, and a signed installer. Package `dist/store/FaceHugger-1.0-2.pkg` uploaded and attached to the ASC draft. Nothing submitted for App Review or released; release remains manual.

App `6817866865`; bundle `dev.zakkeown.FaceHugger`; version `6302c414-5900-40dd-bb0d-2b886d65496b`; build `308a707f-72a8-4801-9dcc-7cb5b3c530fd`; SKU `FACEHUGGER`. Full listing state and remaining gates: [AppStore/README.md](../AppStore/README.md).

## Implemented and verified

- Large-directory responses stream bounded item events with strict JSONL framing and terminal-count checks; oversized or partial results fail explicitly.
- Folder security bookmarks persist in jobs/pairings; independent leases retain access until scans/helpers end. Legacy path-only records remain decodable.
- Python 3.12.14 and 15 runtime packages are pinned with hashes. Direct setup uses isolated support/cache locations. Store downloads no runtime and uses bundled architecture-specific Python, container caches, and explicitly entered Keychain tokens.
- Store package signatures/profile and both native slices verified. Relocated arm64 runtime imports and CLI checks passed. Intel is structurally verified, not executed (no Rosetta).
- 32 Swift and 56 Python tests passed. Direct and Store builds passed.
- Development-signed sandbox probe proved folder read/write, bookmark restoration in a new process, denied access before restoration, and inherited helper permissions. Real sandboxed HF upload downloaded back byte-identically; disposable repository/files cleaned. Actual Store UI scanned a harmless fixture and displayed included-tools settings. See [sandbox-verification.md](sandbox-verification.md).
- Python native notices, wheel notices, and source notices for all 237 HF Xet SBOM identities retained. See [notice audit](third-party-notices.md) for limitations and provenance.

## Owner-approved listing and review access

Free, all current/future territories, Developer Tools, 13+ minimum, approved third-party content-rights declaration. Privacy policy published with public contact zak.k.ai@outlook.com. App Privacy published: User ID and Other User Content, linked for App Functionality, no tracking. Private review contact and restricted-token credentials saved and browser reload-verified.

Retain private dataset `zakkeown/face-hugger-app-review-89503494` and token **Face Hugger App Review** through review; revoke/delete afterward. Token resides in ASC private review credentials, not files/Git. HF requires selected-repository read/write plus gated-request view and allows public reads; no global private/org scope. Do not print ASC review-password fields or screenshot them. Private contact JSON is ignored under `.build`.

## Signing and tools

ASC CLI `/Users/zakkeown/Code/space-case/.tmp/tools/asc/asc`, profile `SpaceCase`, `ASC_TELEMETRY_DISABLED=1`. API auth is in Keychain; CLI web MFA failed historically, while Safari is signed in. Do not recreate the app or retry web MFA for API tasks.

Team `3FMAPDQDGP`. Store application certificate `J96CN8H3CC`, identity `D9C38F064E9E179FDEA737994F4D32550439EEA7`; installer certificate `7HQ7WWX8TW`, identity `4CCB7F23C5F79F2F5AFE4C9D59FB7F9F6FBB2BB3`; profile `6TA8PNK7KK`, **Face Hugger Mac App Store**, UUID `a7216289-cdf0-41be-97ca-718aa5e31617`. Keys are in login Keychain; raw temporary keys/CSRs removed. See [store-build.md](store-build.md).

The original Developer ID-notarized direct beta `dist/beta/FaceHugger-0.1.0-beta.1-universal-notarized.dmg` predates these fixes. Rebuild/notarize a new artifact before distributing current direct-build code. Do not describe the old DMG as containing this work.

## Resume

1. Inspect Git and latest ASC validation; preserve unrelated changes.
2. Finish actual Store screenshots. Native Screenshot launch failed and Preview capture returned to Open; no PNG exported. Manual Shift–Command–5 capture steps are in AppStore/screenshots/README.md. Never manufacture transfer statistics or expose credentials.
3. Resolve [export compliance](export-compliance.md), including the bundled TLS implementation and approved France availability. No exemption declaration was inferred.
4. Complete remaining dependency obligations and clean-machine/Intel/Store recovery verification. Do not claim multi-terabyte testing; owner lacks that disk capacity.
5. Rebuild with a new build number if package resources/code change, upload/attach, validate, then seek explicit submission approval. Preparation is authorized; submission/release has not been requested.

The user approved subagents and test repos with cleanup; the review repo is the explicit persistent exception. Preserve the approved paired-surface/slate-shelf design and friendly facehugger artwork.
