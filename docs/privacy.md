# Face Hugger privacy policy

Effective September 30, 2026. Face Hugger is developed by Zak Keown. For privacy or support requests, contact [zak.k.ai@outlook.com](mailto:zak.k.ai@outlook.com).

## What the app does with your information

Face Hugger is a Mac client for Hugging Face. It sends files you choose to upload, their repository paths, and the requests needed to browse and manage repositories to Hugging Face and its upload infrastructure. These services receive network information such as your IP address. Account authentication uses your Hugging Face access token or an existing local Hugging Face CLI login. Repository requests retrieve account names, organization membership, repository information, and file listings to display in the app.

Your files are transferred to Hugging Face, not to a Face Hugger developer-operated upload server. The developer does not operate an analytics, advertising, or automatic crash-reporting service in the app. Face Hugger disables the Hugging Face Hub SDK's optional telemetry flag. This does not prevent the service from processing the requests and operational information needed to provide uploads and account access.

Hugging Face controls its service-side processing and retention under its [privacy policy](https://huggingface.co/privacy). Repository visibility matters: files in public repositories are accessible to others. Deleting a local queue item or uninstalling Face Hugger does not delete uploaded files or repository history on Hugging Face. Use Hugging Face's repository and account controls for those records.

## Information kept on your Mac

An access token saved through Face Hugger is stored in macOS Keychain. Queue and saved-pairing records store local folder paths, repository identifiers, filters, transfer status, and limited recent failure output. Folder permission bookmarks may be saved to restore access to folders you selected. These records are stored in Face Hugger's Application Support directory. Runtime and dependency caches and Hugging Face upload checkpoints may also be stored locally, including an upload cache inside a selected source folder. Some SDK caches or an existing CLI login can reside in Hugging Face's own cache directory.

The app attempts to redact Hugging Face tokens from displayed and saved process output. File paths, repository names, and other diagnostic details may still appear in logs. Local completion notifications can show a transfer title. macOS controls notification display and permissions.

You can remove saved pairings and finished queue items in the app. Removing the saved account deletes the token saved by Face Hugger; it does not revoke the token at Hugging Face or remove a separate CLI login. To revoke a token, use your Hugging Face account settings. To remove remaining local Face Hugger records, quit the app and remove its Application Support folder after preserving anything you need. Removing source-folder upload caches can discard resumable progress.

## Setup, links, and support

The direct-download edition fetches Python and upload tools during setup from Astral/GitHub and Python package infrastructure. Those providers receive ordinary download requests and associated network information. Opening account, help, or project links sends you to the corresponding third-party website, whose policies apply.

If you email support, the developer receives the address, message, and attachments you send and uses them to respond and investigate the issue. GitHub issues are public: do not post tokens, private datasets, or sensitive logs there. Send only the information needed for support. Contact the address above to request deletion of support correspondence, subject to records that need to be retained for legal obligations or resolving an ongoing issue.

## Changes

This policy will be updated when the app's handling of information changes. The effective date above identifies the current version.
