<p align="center">
  <img src="Resources/Assets.xcassets/Hugger.imageset/hugger.png" width="160" alt="A smiling yellow emoji wrapped by a friendly tan facehugger">
</p>

# Face Hugger

A native Mac upload manager for Hugging Face. Give your big folders a home.

Face Hugger wraps the official `hf upload` CLI in a SwiftUI app with a persistent queue, readable logs, a menu bar companion, and a small repository browser. This is an early **0.1 developer build**, targeting macOS 15 and later.

## What works

- Queue local folders for model or dataset repositories, with destination paths and include/exclude globs.
- Run one upload at a time; stop and resume through HF’s resumable, deduplicating upload pipeline.
- Recover interrupted jobs after relaunch. The queue starts paused so you decide when to continue.
- Browse repository folders, search the current listing, create public or private repositories, and delete individual files after confirmation.
- Connect with a Keychain-stored token or an existing Hugging Face CLI login.
- Keep uploads running when the window closes, optionally prevent idle system sleep, and receive completion notifications.

Progress is honest: the app displays activity and HF logs without inventing a percentage. Preparation, transfer, and commits can overlap. Files may become visible in multiple commits before the entire job finishes.

## Build and run

You need macOS 15+, Xcode with Swift 6 support, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [uv](https://docs.astral.sh/uv/getting-started/installation/).

```sh
brew install xcodegen uv
xcodegen generate
xcodebuild -project FaceHugger.xcodeproj -scheme FaceHugger \
  -configuration Debug -derivedDataPath .build/xcode build CODE_SIGN_IDENTITY=-
open ".build/xcode/Build/Products/Debug/Face Hugger.app"
```

In **Settings**, choose **Set up upload tools**. This installs Python 3.12 and the pinned Hugging Face runtime into an isolated environment under `~/Library/Application Support/Face Hugger/`. Setup needs an internet connection; the app currently looks for `uv` in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`.

Connect with a Hugging Face token that can write to your destination repository. Leaving the token blank uses the existing CLI login, if available. Removing the saved app account does not log you out of the separate HF CLI.

Create or select a repository, choose a local folder, review its destination and filters, then **Upload now** or **Add to queue**. Matching remote paths may be replaced. Other remote files are retained. An upload requires an existing repository; repository creation has an explicit visibility choice.

Closing the window leaves the app and its uploads running in the menu bar. Quitting asks to stop an active upload first. Stopping does not undo files already committed. Resume reruns the job and lets HF reuse previously uploaded content.

## Current limits

- The upload runtime is installed on first use; it is not bundled. There is no signed, notarized release installer yet.
- Uploads run while the app is running. There is no launch agent, scheduled upload service, or upload while the Mac is asleep.
- A failed upload stops the queue. Resume or restart it when you are ready.
- Logs are bounded and session-only. Queue metadata and completed-job history are saved locally.
- Source folders remain live: jobs store a path, not a snapshot. Changing files between attempts changes what the resumed job uploads.
- Repository management covers models and datasets, browsing, creation, and individual file deletion. It does not include Spaces, branches, file moves, card editing, or whole-repository deletion.
- HF credentials and a real destination are needed to test an upload. Automated tests use mocks and local subprocesses; they do not upload to or mutate your repositories.

## Checks

```sh
Scripts/check.sh
```

This runs the Swift core tests and Python bridge tests without needing HF credentials or the HF Python package. To also generate and build the macOS app:

```sh
Scripts/check.sh --build
```

The GitHub Actions workflow runs both suites and an ad-hoc-signed app build on a macOS runner. See [architecture](docs/architecture.md) and [visual direction](docs/design.md) for implementation details.

## Upload engine

The runtime pins `huggingface_hub==2.0.0` and invokes `hf upload`. Current Hugging Face supports large, resumable folder uploads through that command; the old `upload-large-folder` command has been removed in 2.0. See the official [upload guide](https://huggingface.co/docs/huggingface_hub/guides/upload) and [CLI reference](https://huggingface.co/docs/huggingface_hub/package_reference/cli).

Face Hugger is an independent project, not an official Hugging Face application.
