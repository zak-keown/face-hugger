<p align="center">
  <img src="Resources/Assets.xcassets/Hugger.imageset/hugger.png" width="160" alt="Face Hugger mascot">
</p>

# Face Hugger

A native Mac upload manager for Hugging Face. Give your big folders a home.

Face Hugger brings a local file preview, remote repository browser, and persistent upload queue into one SwiftUI workspace for macOS 15 and later. **Native backend build 1.0 (4) is built and signed; release validation is still in progress.** Existing direct beta and Store build 3 artifacts use the older Python/Hugging Face CLI backend; their verification results do not establish build-4 behavior.

## Workspace

- Prepare model or dataset folders with destination paths and include/exclude globs.
- Review remote path conflicts before uploading. Matching paths do not prove identical contents.
- Queue jobs, stop transfers, and choose when to retry interrupted work.
- Browse remote folders, create public or private repositories, and delete individual files after confirmation.
- Connect using a Hugging Face access token stored in macOS Keychain.
- Save folder–repository pairings, keep uploads running after closing the window, optionally prevent idle sleep, and receive completion notifications.

The native engine uses Apple URLSession and CryptoKit against Hugging Face HTTP APIs. It needs no Python installation or bundled workers. Live multipart transfer, cancellation, fresh-process resume, and downloaded hashes have passed verification. Recovery reuses confirmed files; unfinished multipart transfers restart. It does not implement Xet chunk-level deduplication or promise multi-terabyte performance.

## Build and run

You need macOS 15+, Xcode with Swift 6 support, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project FaceHugger.xcodeproj -scheme FaceHugger \
  -configuration Debug -derivedDataPath .build/xcode build CODE_SIGN_IDENTITY=-
open ".build/xcode/Build/Products/Debug/Face Hugger.app"
```

Connect with a token that can write to the chosen repository. Select a local folder and destination, review filters, then start the upload. Matching remote paths may be replaced; other files remain. Source folders stay live rather than being snapshotted. The native engine checks for changes and requires a new job when a saved upload’s source changes. Stopping does not undo remote commits. Closing the window leaves the app running; quitting stops an active transfer.

[Privacy policy](docs/privacy.md) · [Support](https://github.com/zak-keown/face-hugger/issues) · [Native release gate](docs/native-backend-release.md)

## Limits and verification

Uploads require the app to remain running and the Mac awake. There is no scheduled upload service. Repository management is limited to models and datasets; Spaces, branches, moves, card editing, and whole-repository deletion are outside scope. Logs are bounded and session-only; queue and pairing metadata persist locally.

`Scripts/check.sh` is the repository check entry point. Some Python bridge tests and old live-test scripts remain as historical regression evidence; they are not native-engine integration tests. The production native live test is in `Scripts/NativeSmoke`; see the native release gate for its results. Tests that mutate remote repositories must use explicitly authorized disposable fixtures and verify cleanup.

The Store build uses [project-store.yml](project-store.yml) and [Store packaging](docs/store-build.md). Packaging performs a native-only binary/dependency audit before signing the installer. The older Developer ID beta packaging flow is documented in [releasing.md](docs/releasing.md); runtime setup instructions there describe the historical beta until that flow is revalidated.

The native build 4 has passed its package audit, is processed and attached to the App Store draft, and has an Apple-verified OS-only encryption flag. The old build-3 third-party TLS declaration remains historical. No App Review submission or release has occurred.

Face Hugger is an independent project, not an official Hugging Face application.
