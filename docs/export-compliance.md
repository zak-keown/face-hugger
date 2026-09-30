# Encryption preparation — September 30, 2026

No export-compliance exemption or classification has been submitted. The approved availability includes France.

## Technical facts

Face Hugger authenticates and transfers repository data over HTTPS to Hugging Face. The Store package includes CPython 3.12.14 with OpenSSL 3.5.8 and HF/Xet networking dependencies. Its encryption is therefore not exclusively provided by Apple's operating system. The app does not implement a proprietary cryptographic protocol; this does not by itself determine an exemption. Dependency inventories are retained under Resources/ThirdParty.

## Remaining action

Open App Store Connect → Face Hugger → App Information → App Encryption Documentation, or the build's Manage compliance action. Answer against the bundled implementation and intended distribution. Retain the resulting classification and upload required documents before review; add an Info.plist compliance value only when the determination supports it.

Apple's [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/) distinguishes OS-only encryption from industry-standard algorithms supplied by the app and lists a French declaration for the latter when distributing in France. This makes documentation/classification a concrete unresolved step for the current bundle and territories. Do not silently exclude France or claim OS-only encryption to bypass it. The release owner must supply any required declaration or obtain a qualified determination of an applicable exemption.

See Apple's [questionnaire/documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/). This file records engineering evidence and outstanding work, not a legal classification.
