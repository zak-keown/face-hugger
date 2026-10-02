# App Store release preparation

[Face Hugger in App Store Connect](https://appstoreconnect.apple.com/apps/6817866865) is a **1.0 draft**, with manual release. Nothing has been submitted for App Review or released. SKU `FACEHUGGER`, bundle `dev.zakkeown.FaceHugger`, version ID `6302c414-5900-40dd-bb0d-2b886d65496b`.

## Completed

- English listing metadata (including the dataset-card editor), Developer Tools category, copyright, support/marketing URLs, and published privacy policy.
- Free pricing; all 175 current territories and future territories enabled.
- Age questionnaire, including user-generated content and a 13+ minimum matching HF account requirements.
- Owner-confirmed third-party content rights saved.
- Owner-approved App Privacy published: User ID and Other User Content, linked to user for App Functionality, no tracking.
- Private App Review contact, scoped token, and working-access instructions saved, including dataset-card steps. Keep the dedicated review repository/token until review completes; see [review-access.json](review-access.json). Credentials and private phone are not in Git.
- Universal, sandboxed native Store package **1.0 (6)** built, signed, audited, uploaded, processed VALID, and attached to the draft on October 2, 2026 (readback verified). Build ID `62d74e22-0d89-4f50-900c-a6f1a6fbf043`. It is build 5's code with the original folder-hugging icon and mascot. FoundationModels is weak-linked, so the app still launches on macOS 15. See [bundle audit](../docs/verification/native-bundle-build6.json).
- Build **1.0 (5)** (`dcb5fca3-f5e0-4020-91a3-de0ac7512207`) added the dataset-card editor but carries the retired icon. Build **1.0 (4)** (`f701748b-9e6a-45e1-a4cf-771e656f7dad`) lacks the dataset-card editor. Both remain uploaded and VALID but unattached; do not reattach either.
- Native build encryption readback is `usesNonExemptEncryption=false`; Apple system networking and cryptography replace the old third-party runtime. No French document is required by Apple’s OS-only category. See [verified build facts](native-encryption-build6.json).
- Four genuine build-6 screenshots (workspace, on-device dataset-card draft, file filters, saved pairings) replaced the build-3 set on October 2, 2026 and processed COMPLETE. See [capture provenance](screenshots/README.md).
- CLI readiness validation with build 6 attached (October 2, 2026): **0 errors, 0 warnings, 0 blocking findings**. Manual release and API-unverifiable privacy publication remain informational notices.

## Remaining release work

1. **Review access:** on October 2, 2026 the development-signed app's saved token (entered from the restricted review credentials during the build-3 capture) still authenticated and listed the private review repository. Confirm the review details' password field holds that same token; an unusable token is an automatic rejection.
2. **Release validation:** run on macOS 15 (the app has only run on macOS 27), clean-machine installation, longer real-network interruption testing, and Intel execution (or Rosetta as a stand-in). The build-5/6 code passed 71 Swift tests, and both builds passed the native bundle audit on their expanded installers. Native cancellation, fresh-process resume, downloaded hashes, and a signed sandboxed UI upload passed. Intel slices are structurally verified but have not run on this Mac. See [native evidence](../docs/native-backend-release.md).
3. Confirm account-level agreements, Regulations and Permits declarations, and territory requirements, recheck published App Privacy in the browser, then obtain release-owner approval to submit. Nothing has been submitted or released.

The old build-3 encryption declaration and French filing drafts are historical records. They are not the encryption facts of the native builds 4 to 6. The new package includes only its applicable PSF wildcard-attribution notice; no Python/OpenSSL/Xet runtime is bundled.

[validation.json](validation.json) is CLI readiness evidence, not App Review approval. App Privacy publication was verified in the browser because the public API cannot verify it. The original notarized direct beta remains a separate, older artifact. See [handoff](../docs/handoff.md) and [Store build instructions](../docs/store-build.md).
