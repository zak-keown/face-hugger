# Native upload smoke test

Opt-in test for the production Swift engine, using a disposable private Hugging Face dataset and synthetic files. It creates remote content and deletes the test repository afterward. Credentials must already be available; they are never logged, saved to disk, or passed in arguments.

Build on macOS:

```sh
mkdir -p .build/native-smoke
swiftc -swift-version 6 -parse-as-library Sources/FaceHuggerCore/*.swift Scripts/NativeSmoke/main.swift -o .build/native-smoke/probe
```

Run with `HF_TOKEN` in the environment and `--run-live`, or use the development-only `run.py` launcher from an existing Hugging Face Python environment. That launcher reads the existing token and starts Swift; all network activity and cryptography occur in native code. Neither launcher nor test executable ships in the app.

The test uploads a 16 MiB random payload and a text file, excludes another file, cancels after more than 1 MiB has transferred, and resumes in a fresh native process from disk checkpoints. It verifies downloaded hashes, repeats the completed upload without new commits, deletes a remote file, then verifies that the changed remote head invalidates old receipts. Cleanup checks that the disposable repository returns 404 and removes the fixtures. A sanitized ledger is written to `.build/native-smoke/result.json` before creation and after cleanup; inspect it if a run is interrupted.

This is bounded integration evidence, not a multi-terabyte performance test or a prolonged network-outage test. It does not replace the signed app's sandbox/bookmark/UI checks. Interrupted multipart uploads restart; completed LFS objects can be reused by the service.
