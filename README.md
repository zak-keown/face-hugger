<p align="center">
  <img src="Resources/Assets.xcassets/Hugger.imageset/hugger.png" width="160" alt="A smiling yellow emoji wrapped by a friendly tan facehugger">
</p>

# Face Hugger

A native Mac upload manager for Hugging Face. Give your big folders a home.

Face Hugger wraps the official `hf upload` CLI in a SwiftUI app with a persistent queue, readable logs, a menu bar companion, and a small repository browser. This is an early **0.1 beta**, targeting macOS 15 and later.

## What works

- Queue local folders for model or dataset repositories, with destination paths and include/exclude globs.
- Run one upload at a time; stop and resume through HF’s resumable, deduplicating upload pipeline.
- Recover interrupted jobs after relaunch. The queue starts paused so you decide when to continue.
- Browse repository folders, search the current listing, create public or private repositories, and delete individual files after confirmation.
- Connect with a Keychain-stored token or an existing Hugging Face CLI login.
- Keep uploads running when the window closes, optionally prevent idle system sleep, and receive completion notifications.

Progress is honest: the app displays the CLI’s reported preparation, upload/reuse, data-transfer, and commit counts without inventing an overall percentage. Unknown output formats fall back to readable logs. Stages can overlap, and files may become visible in multiple commits before the entire job finishes.

## Build and run

You need macOS 15+, Xcode with Swift 6 support, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project FaceHugger.xcodeproj -scheme FaceHugger \
  -configuration Debug -derivedDataPath .build/xcode build CODE_SIGN_IDENTITY=-
open ".build/xcode/Build/Products/Debug/Face Hugger.app"
```

In the direct-download edition's **Settings**, choose **Set up upload tools**. This installs Python 3.12.14 and the checksum-locked Hugging Face dependencies under `~/Library/Application Support/Face Hugger/`, with explicit `python/`, `setup-cache/`, and `runtime-v3/` directories. Setup downloads pinned uv 0.12.18 from its official GitHub release and verifies its SHA-256 before execution. No Homebrew or terminal setup is required. The older `runtime/` directory is left intact during migration; the updated app asks for setup once to install the new locked runtime. Hugging Face's own login/cache locations remain compatible with an existing CLI installation.

The App Store build under development embeds its upload runtime and does not download executable tools at first launch. See [Store preparation](docs/store-build.md) for its current validation limits.

[Privacy policy](docs/privacy.md) · [Support](https://github.com/zak-keown/face-hugger/issues)

Connect with a Hugging Face token that can write to your destination repository. Leaving the token blank uses the existing CLI login, if available. Removing the saved app account does not log you out of the separate HF CLI.

Create or select a repository, choose a local folder, review its destination and filters, then **Upload** or **Add to queue**. Matching remote paths may be replaced. Other remote files are retained. An upload requires an existing repository; repository creation has an explicit visibility choice.

Closing the window leaves the app and its uploads running in the menu bar. Quitting asks to stop an active upload first. Stopping does not undo files already committed. Resume reruns the job and lets HF reuse previously uploaded content.

## Current limits

- The upload runtime is installed on first use; it is not bundled. See [beta packaging](docs/releasing.md) for universal DMG builds and signing/notarization.
- Uploads run while the app is running. There is no launch agent, scheduled upload service, or upload while the Mac is asleep.
- A failed upload stops the queue. Resume or restart it when you are ready.
- Logs are bounded and session-only. Queue metadata and completed-job history are saved locally.
- Source folders remain live: jobs store a path, not a snapshot. Changing files between attempts changes what the resumed job uploads.
- Repository management covers models and datasets, browsing, creation, and individual file deletion. It does not include Spaces, branches, file moves, card editing, or whole-repository deletion.
- Default automated tests use mocks and local subprocesses; they do not upload to or mutate your repositories. An opt-in live test exercises real uploads and repository operations with temporary synthetic data.

## Developer beta packaging

`Scripts/package-beta.sh` builds a universal Release app and a drag-to-Applications DMG in `dist/beta`, with a SHA-256 checksum. Ad-hoc builds are explicitly labeled; a Developer ID identity plus a notarization profile or configured `asc` authentication produces a notarized package. See [release instructions](docs/releasing.md).

## Checks

```sh
Scripts/check.sh
```

This runs the Swift core tests and Python bridge tests without needing HF credentials or the HF Python package. To also generate and build the macOS app:

```sh
Scripts/check.sh --build
```

The GitHub Actions workflow runs both suites and an ad-hoc-signed app build on a macOS runner. See [architecture](docs/architecture.md) and [visual direction](docs/design.md) for implementation details.

### Optional live integration test

After app runtime setup, run:

```sh
"$HOME/Library/Application Support/Face Hugger/runtime/bin/python3" Scripts/live_smoke.py --run-live
```

This explicitly creates a temporary **private model** and **public dataset** in your authenticated HF account, uploads synthetic fixtures including a 64 MiB random file, checks downloaded hashes, interrupts/resumes the CLI, and exercises replacement and deletion. It deletes the test repos in a `finally` block and verifies their absence. A temporary ledger records exact repository IDs before creation and any cleanup failures. Do not run it without permission to create and delete repositories. It never uploads your project files and is excluded from CI. See [verification results](docs/verification.md).

## Upload engine

The runtime pins `huggingface_hub==2.0.0` and invokes `hf upload`. Current Hugging Face supports large, resumable folder uploads through that command; the old `upload-large-folder` command has been removed in 2.0. See the official [upload guide](https://huggingface.co/docs/huggingface_hub/guides/upload) and [CLI reference](https://huggingface.co/docs/huggingface_hub/package_reference/cli).

Face Hugger is an independent project, not an official Hugging Face application.

For bounded local stress checks, run the managed Python with `Scripts/reliability.py`. It scans 10,000 tiny files, exercises comparison limits, and runs repeated process interruption/restart fixtures. Injected connection failures do not represent a prolonged real network outage.
