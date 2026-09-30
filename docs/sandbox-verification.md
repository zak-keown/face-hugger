# Sandbox verification

Verified locally on September 30, 2026, on Apple Silicon. These are development-signed sandbox checks, not App Store review or a complete sandbox upload qualification.

## Signed source-access probe

`Scripts/sandbox_probe.py` builds a separate `dev.zakkeown.FaceHugger.SandboxProbe` app using `Scripts/SandboxProbe/main.swift` and the production `FolderAccess` helper. The app and bundled Python native code were signed with the same local Apple Development identity. The app used `Resources/Store.entitlements`; helper executables used `Resources/StoreHelper.entitlements`. Signature verification passed.

Using the native folder picker, the probe selected only `/private/tmp/face-hugger-sandbox-probe-source`, containing generated public test data. Both runs passed:

| Check | Observed result |
| --- | --- |
| First selection | Process 39773 created a scoped bookmark; bundled Python read and wrote the fixture. |
| Quit and relaunch | New process 45495 restored the persisted bookmark without another folder picker. |
| Before restoration | Reading the fixture marker failed, confirming the fresh process lacked that folder access. |
| After restoration | Bundled Python read and wrote the fixture successfully; exit status 0. |
| Runtime | Python 3.12.14 and huggingface_hub 2.0.0 imported successfully in both runs. |
| Sandbox | The process reported the probe's sandbox container and container home directory. |

Generated local reports remain in `.build/sandbox-probe/results.json` (untracked). Reports were exported by the probe into its explicitly selected fixture folder; no container privacy permissions were changed.

## Actual Store app

Launched the exact development-signed build at `.build/store-xcode/Build/Products/Debug/Face Hugger.app`. Native UI inspection confirmed:

- Settings displayed **Upload tools are included** and **Upload tools are updated with the app through the App Store.** No runtime download/setup controls appeared.
- Choosing the dedicated fixture through the native picker produced a successful preview of six files, zero excluded, totaling approximately 1 KB. This exercised the actual app's bundled Python scan process inside its sandbox.
- No account was connected and no upload was started.

The app and probe were closed after verification. The dedicated fixture directory was removed. Probe reports and reproducible source scripts were retained; app containers were not deleted.

## Actual sandbox bridge → HF CLI upload

`Scripts/sandbox_upload_smoke.py --run-live` subsequently verified a real upload from the signed probe using the production `Resources/bridge.py` and a second bundled Python process running the official HF CLI. Probe process 73013 launched bridge process 79318. The bridge reported pipeline progress, then completion with exit status 0, from the expected sandbox container.

The harness created one disposable **private** repository and uploaded exactly two generated files (48 bytes and 4,096 bytes) under a nested destination. The host SDK downloaded both and verified their bytes. The repository's file set matched the fixture set. The existing test credential was passed only through process environment, never command arguments or a credential file; captured evidence was redacted before writing.

The harness's `finally` cleanup deleted the repository, verified it no longer existed, stopped the probe, and removed the fixture directory. The completed report is `.build/sandbox-probe/live-upload-result.json` (untracked), with `passed`, `deleted`, and `fixture_removed` all true. No test repository remains from this run.

## Reproduce

1. Stage the native runtime using `Scripts/stage-store-runtime.py --arch arm64`.
2. Build with `python3 Scripts/sandbox_probe.py --runtime .build/store-runtime/UploadRuntime.bundle/Contents/Resources/arm64/python --identity YOUR_APPLE_DEVELOPMENT_IDENTITY`.
3. Create a dedicated `/private/tmp/face-hugger-sandbox-probe-source` folder with a harmless fixture.
4. Open `.build/sandbox-probe/Face Hugger Sandbox Probe.app`, select that folder, and verify **PASS · selection**.
5. Quit the probe. Relaunch using `open -n '.build/sandbox-probe/Face Hugger Sandbox Probe.app' --args --restore` and verify **PASS · restored**.
6. Inspect the generated fixture reports, check that process IDs differ and `pre_restore_read_succeeded` is false, then close the probe and clean the fixture.

For the live integration check, run the managed Python with `Scripts/sandbox_upload_smoke.py --run-live`, then select the dedicated fixture in the probe's native picker. This opt-in mode creates a private repository, uploads synthetic files, verifies downloads, and performs cleanup automatically. It requires an existing HF credential with repository write access. The local-only selection/restoration mode makes no HF requests.

These checks establish source access across relaunch and a small authenticated upload through the sandboxed subprocess chain. They do not establish sandbox stop/resume or network-outage recovery, Intel execution, full Store-app account flows, Mac App Store acceptance, or future runtime behavior. Those require separate qualification.

## Store UI upload during screenshot preparation

On September 30, the development-signed Store 1.0 (3) UI selected a real harmless dataset fixture, applied `logs/**`, uploaded four files totaling 508 bytes through the restricted App Review credential, and displayed Upload complete with the remote files visible. The four screenshots under `AppStore/screenshots/1.0-build3` retain this real UI evidence. This extends the earlier probe with an actual app UI upload; it is still not a stop/resume, outage, Intel, or large-volume claim. Review repository/token and harmless review sample remain available through review.
