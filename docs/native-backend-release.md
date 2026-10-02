# Native backend — builds 4 to 6

Store version **1.0 (4)** replaces the Python/Hugging Face CLI runtime with Swift code using **URLSession** for HTTPS and **CryptoKit** for SHA-256. The Transfer Bench interface, queue archive, Keychain account, and folder bookmarks are retained. No Python/OpenSSL/Xet runtime or executable setup download is included.

## Behavior

The native client supports account/organization identity, model and dataset listings, repository creation, remote browsing and file deletion, HF-compatible include/exclude patterns, preview comparisons, and full upload conflict preflight. Authentication stays on the Hub origin; cross-origin redirects strip credentials. Metadata responses and preview listings have explicit limits. Reads, negotiation, and idempotent uploads have bounded retries; ambiguous commit responses never count as completion.

Local manifests and complete path indexes use disk storage. Files are hashed in 1 MiB reads. LFS basic and multipart transfers use file-backed requests and at most one staged multipart piece. Commits contain at most 100 files and 16 MiB of inline file content. Very large files that the server designates for inline upload fail with guidance to configure LFS.

Checkpoint receipts contain file metadata/hashes and confirmed commit state, not tokens or signed URLs. Resume rescans and rehashes the source and checks the current remote head before reusing receipts. Source changes require a new job. Remote changes invalidate receipts. Removing a queue item removes its native checkpoints. Stopping leaves previous remote commits intact.

Uploads currently hash and transfer files sequentially. Recovery is at file level: an unfinished multipart object restarts, while completed LFS objects can be reused by the service. This does not implement Xet chunk-level deduplication, whole-folder atomic snapshots, or coordination with concurrent remote writers.

## Verification on September 30, 2026

- **66 Swift tests passed:** 46 XCTest cases plus 20 Swift Testing cases. These include native HTTP bounds/cancellation/redirects, byte-exact Unicode paths, batch limits, source mutation, remote-head changes, and uncertain commit recovery.
- Historical bridge regression suite: 56 tests run, 3 skipped, no failures. It is not evidence for native networking.
- Native wildcard matcher: 145,681 differential cases against Python `fnmatchcase`, no mismatches. The derived bracket-range normalization retains its PSF notice in `Resources/PythonFnmatchLicense.txt`; no Python executable is shipped.
- Live native production-engine test: private dataset, unique 16 MiB payload plus a text file, filter exclusion, cancellation after 2 MiB, successful resume in a **fresh process**, byte-identical downloads, confirmed-commit reuse, and remote deletion followed by restored content. Repository deletion was verified by HTTP 404 and local fixtures removed. [Sanitized result](verification/native-live-2026-09-30.json), [test instructions](../Scripts/NativeSmoke/README.md).
- Development-signed sandboxed app: restored the existing selected-folder bookmark, authenticated from Keychain, browsed the dedicated private review repo, and uploaded the four approved synthetic fixture files successfully. The tiny UI upload finished before its Stop button could be clicked; cancellation evidence comes from the production-engine integration test and unit tests.
- The signed app's packaged icon was extracted and visually confirmed as the approved cartoon facehugger on blue. The older notification icon observed locally appears to be macOS caching; notification settings were not reset.

## Exact package audit

`dist/store/FaceHugger-1.0-4.pkg` is 5,212,908 bytes. SHA-256:

```text
829f0efc82c06cd28f5a8d16f25131b5b39de3f4cfcd0dfe451e7a08b296b1cb
```

The clean Release bundle and the app expanded from the signed installer both passed `Scripts/package-store.sh --audit-app`. They contain one universal arm64/x86_64 executable, with dynamic dependencies confined to `/System/Library` and `/usr/lib`. Strict signing, sandbox/network entitlements, provisioning, architecture slices, forbidden-runtime resource checks, and selected symbol checks passed. The expanded executable is byte-identical to the pre-package executable. The app occupies about 11 MiB on disk.

Source/link-input review found only project Swift sources and system frameworks/libraries, with no external package, binary, dynamic-loading path, or active process launcher. Only assets and the narrow PSF attribution notice are resources. This source review complements the binary audit, which alone cannot identify every possible statically embedded implementation. Audit outputs are under `.build/store-package/native-audit/`.

## Build 5 — dataset-card editor

Store version **1.0 (5)** is build 4's native backend plus the dataset-card editor. Apple processed build `dcb5fca3-f5e0-4020-91a3-de0ac7512207` as VALID with `usesNonExemptEncryption=false`. On October 2, 2026 it replaced build 4 on the draft (readback verified), and readiness validation still reported 0 errors, 0 warnings, and 0 blocking findings. Build 6 replaced it the same day.

`dist/store/FaceHugger-1.0-5.pkg` is 5,498,844 bytes. SHA-256:

```text
b425bd17e53f80640f5e065f93da83c04040c8aec3c8c74a2770b0d2c3d81f91
```

The app expanded from the signed installer passed `Scripts/package-store.sh --audit-app`, and its executable is byte-identical to the Release build. The only dependency change from build 4 is `FoundationModels.framework`, weak-linked in both slices, so macOS 15 launches without it. Resources are unchanged. On the same date `Scripts/check.sh` passed 71 Swift tests (46 XCTest, 25 Swift Testing) and the historical Python suite (56 run, 3 skipped). [Audit record](verification/native-bundle-build5.json).

## Build 6 — original icon, attached to the App Store draft

Store version **1.0 (6)** changes only artwork: the app icon and in-app mascot are now an original coral creature hugging a folder, replacing the Hugging Face emoji and Alien-style creature. With code signatures removed, its executable is byte-identical to build 5's; dependencies and resources are unchanged apart from the asset catalog and icon file. Apple processed build `62d74e22-0d89-4f50-900c-a6f1a6fbf043` as VALID with `usesNonExemptEncryption=false`. It was attached to the draft on October 2, 2026 (readback verified), and readiness validation reported 0 errors, 0 warnings, and 0 blocking findings.

`dist/store/FaceHugger-1.0-6.pkg` is 3,691,197 bytes. SHA-256:

```text
e0faa8b3e235a217ffd17e507a233249e6b87f5244a8728606ca374bd3e2047b
```

Both the Release bundle and the app expanded from the signed installer passed `Scripts/package-store.sh --audit-app`, and the expanded executable is byte-identical to the Release build. macOS 27 renders the packaged icon at full size beside system icons, without a fallback plate. [Audit record](verification/native-bundle-build6.json).

## Encryption and release state

Build 4's actual Info.plist contains `ITSAppUsesNonExemptEncryption = false`. Its encryption is confined to Apple system APIs. Apple's [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) states that OS-only encryption requires no documentation in App Store Connect; this is the basis for the new build's answer.

Build 3 still contains third-party TLS. Its prior non-exempt declaration and French filing drafts remain historical records and must not be relabeled as OS-only. Apple processed build `f701748b-9e6a-45e1-a4cf-771e656f7dad` as VALID; builds 5 and then 6 have since replaced it on the draft. The API confirms `usesNonExemptEncryption=false`. Readiness validation reports 0 errors, 0 warnings, and 0 blocking findings; manual release and public-API privacy verification are informational notices. See the [App Store draft record](../AppStore/README.md). No App Review submission or public release has been performed.

Remaining release validation includes running on macOS 15 (the app has only run on macOS 27), actual Intel execution, clean-machine installation, longer real-network interruption testing, and updated native-build screenshot evidence where required. A valid Intel slice is not proof of execution on Intel hardware. No multi-terabyte performance claim is made. An independent AppModel/Services review attempt was blocked by tool failures; do not count it as a completed review.
