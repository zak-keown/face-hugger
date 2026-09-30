# App Store release preparation

[Face Hugger in App Store Connect](https://appstoreconnect.apple.com/apps/6817866865) is a **1.0 draft**, with manual release. Nothing has been submitted for App Review or released. SKU `FACEHUGGER`, bundle `dev.zakkeown.FaceHugger`, version ID `6302c414-5900-40dd-bb0d-2b886d65496b`.

## Completed

- English listing metadata, Developer Tools category, copyright, support/marketing URLs, and published privacy policy.
- Free pricing; all 175 current territories and future territories enabled.
- Age questionnaire, including user-generated content and a 13+ minimum matching HF account requirements.
- Owner-confirmed third-party content rights saved.
- Owner-approved App Privacy published: User ID and Other User Content, linked to user for App Functionality, no tracking.
- Private App Review contact, scoped token, and working-access instructions saved. Keep the dedicated review repository/token until review completes; see [review-access.json](review-access.json). Credentials and private phone are not in Git.
- Universal, sandboxed Store package **1.0 (2)** built, signed, uploaded, and attached to the draft. Build ID `308a707f-72a8-4801-9dcc-7cb5b3c530fd`.

## Remaining release work

1. **Final screenshots:** capture actual Store UI states, verify dimensions, then upload. Native Screenshot and Preview capture failed to export images in this session; [capture plan](screenshots/README.md) records the manual route.
2. **Export compliance:** complete Apple's encryption questionnaire and any required documentation. The runtime contains OpenSSL and third-party TLS, so it is not limited to OS-provided encryption. France is included in the approved territories. See [technical inventory and next steps](../docs/export-compliance.md); no exemption was asserted.
3. **Dependency obligations:** retain and check bundled native dependency notices; see [audit scope](../docs/third-party-notices.md). Collection coverage is not a blanket legal conclusion.
4. **Release verification:** clean-machine installation, full Store UI upload/stop/resume and outage recovery, and Intel execution. Intel slices pass structural checks but have not run on this Mac. No multi-terabyte claim is made.
5. Check account-level agreements and territory-specific requirements in ASC before submission, then obtain release-owner approval to submit.

[validation.json](validation.json) is CLI readiness evidence, not App Review approval. App Privacy publication was verified in the browser because the public API cannot verify it. The original notarized direct beta remains a separate, older artifact. See [handoff](../docs/handoff.md) and [Store build instructions](../docs/store-build.md).
