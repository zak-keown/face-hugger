# Encryption preparation — September 30, 2026

**Current direction:** owner paused the filing path in favor of Apple-native networking. The [native transport proof](../Experiments/NativeTransport/README.md) passed a real 16 MiB multipart upload/download with only Apple networking/hashing in the transfer executable. Production build 3 is unchanged and still contains third-party crypto; its existing answers remain accurate. Do not treat the experiment as clearance for that build.

An encryption declaration was created in ASC on September 30, 2026: `deb48a27-898e-44dc-8da5-77c2cf681899`. It records third-party cryptography, no proprietary algorithms, and France availability. Apple returned `exempt: false`, state `CREATED`. Build 3 now has `usesNonExemptEncryption: true`. No supporting document or approval code exists yet.

The assignment command returned success, but readback still showed no linked builds and validation reports a missing declaration. Do not describe this as approved or successfully associated until verified. See [encryption.json](../AppStore/encryption.json).

## Technical facts

Face Hugger authenticates and transfers repository data over HTTPS to Hugging Face. The Store package includes CPython 3.12.14 with OpenSSL 3.5.8 and HF/Xet networking dependencies. Its encryption is therefore not exclusively provided by Apple's operating system. The app does not implement a proprietary cryptographic protocol; this does not by itself determine an exemption. Dependency inventories are retained under Resources/ThirdParty.

## Remaining action

Open App Store Connect → Face Hugger → App Information → App Encryption Documentation, or the build's Manage compliance action. Answer against the bundled implementation and intended distribution. Retain the resulting classification and upload required documents before review; add an Info.plist compliance value only when the determination supports it.

Apple's [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/) distinguishes OS-only encryption from industry-standard algorithms supplied by the app and lists a French declaration for the latter when distributing in France. This makes documentation/classification a concrete unresolved step for the current bundle and territories. Do not silently exclude France or claim OS-only encryption to bypass it. The release owner must supply any required declaration or obtain a qualified determination of an applicable exemption.

See Apple's [questionnaire/documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/). This file records engineering evidence and outstanding work, not a legal classification.

## Filing materials prepared

The owner requested filing preparation while keeping France enabled. The official dynamic XFA form is preserved unchanged in `output/pdf/ANSSI-formulaire-officiel-XFA.pdf`. A three-page French worksheet and six-page technical PDF are in `output/pdf/`, with editable sources in `docs/encryption-filing-worksheet.md` and `docs/encryption-technical-description.md`. All authored pages were rendered and visually inspected. These are unsigned preparation documents, not approval evidence. Owner identity/address/nationality, signature, operation/classification choices and any required company evidence remain to be completed locally. Nothing was sent to ANSSI.

## Browser verification

The live App Information questionnaire was inspected on September 30. Selecting standard third-party encryption and France=Yes explicitly requires a **French encryption declaration approval form**; Save is disabled until a file is attached. The dialog was cancelled without a second declaration or document upload. The existing API-created row appears as Upload Failed because it has no document; API state remains CREATED. The unsigned preparation PDFs are not an acceptable substitute for the requested approval form.
