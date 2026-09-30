# App Store release preparation

[Face Hugger in App Store Connect](https://appstoreconnect.apple.com/apps/6817866865) is a **1.0 draft**, with manual release. Nothing has been submitted for App Review or released. SKU `FACEHUGGER`, bundle `dev.zakkeown.FaceHugger`, version ID `6302c414-5900-40dd-bb0d-2b886d65496b`.

## Completed

- English listing metadata, Developer Tools category, copyright, support/marketing URLs, and published privacy policy.
- Free pricing; all 175 current territories and future territories enabled.
- Age questionnaire, including user-generated content and a 13+ minimum matching HF account requirements.
- Owner-confirmed third-party content rights saved.
- Owner-approved App Privacy published: User ID and Other User Content, linked to user for App Functionality, no tracking.
- Private App Review contact, scoped token, and working-access instructions saved. Keep the dedicated review repository/token until review completes; see [review-access.json](review-access.json). Credentials and private phone are not in Git.
- Universal, sandboxed native Store package **1.0 (4)** built, signed, audited, uploaded, processed VALID, and attached to the draft. Build ID `f701748b-9e6a-45e1-a4cf-771e656f7dad`.
- Native build encryption readback is `usesNonExemptEncryption=false`; Apple system networking and cryptography replace the old third-party runtime. No French document is required by Apple’s OS-only category. See [verified build facts](native-encryption-build4.json).
- Current CLI readiness validation: **0 errors, 0 warnings, 0 blocking findings**. Manual release and API-unverifiable privacy publication remain informational notices.

## Remaining release work

1. **Release validation:** clean-machine installation, longer real-network interruption testing, and actual Intel execution. Native cancellation, fresh-process resume, downloaded hashes, and a signed sandboxed UI upload passed. Intel slices are structurally verified but have not run on this Mac. See [native evidence](../docs/native-backend-release.md).
2. **Screenshots:** four genuine Store build-3 captures remain uploaded and COMPLETE. Their Transfer Bench layout remains representative; retain the [capture provenance](screenshots/README.md). Refresh them if visible workflows change before submission.
3. Confirm account-level agreements and territory requirements, recheck published App Privacy in the browser, then obtain release-owner approval to submit. Nothing has been submitted or released.

The old build-3 encryption declaration and French filing drafts are historical records. They are not the encryption facts of the selected native build 4. The new package includes only its applicable PSF wildcard-attribution notice; no Python/OpenSSL/Xet runtime is bundled.

[validation.json](validation.json) is CLI readiness evidence, not App Review approval. App Privacy publication was verified in the browser because the public API cannot verify it. The original notarized direct beta remains a separate, older artifact. See [handoff](../docs/handoff.md) and [Store build instructions](../docs/store-build.md).
