# Verification — September 30, 2026

Tested on Apple silicon with macOS 27, Xcode 27, and the managed Python 3.12 runtime using `huggingface_hub==2.0.0`.

## Automated checks

`Scripts/check.sh` passes 11 Swift tests and 17 Python tests. Coverage includes queue ordering, stop/start races, stale completions, recovery, destination validation, CLI argument handling, progress parsing, token redaction, and real local subprocess termination. The native Debug application also builds with ad-hoc signing.

## Live Hugging Face checks

Two successful runs of `Scripts/live_smoke.py --run-live` each created a private model repository and a public dataset repository using synthetic fixtures only. Both runs verified:

- Explicit visibility and repository listing.
- Include/exclude filters, spaces and Unicode in paths, and downloaded SHA-256 hashes.
- Unchanged repeat uploads and replacement of changed files while preserving unrelated remote files.
- Explicit remote file deletion.
- Interruption of the real upload CLI and successful resume of a 64 MiB random payload, with its downloaded hash verified.

The second run observed CLI pipeline progress before interruption. These checks establish successful interruption and resume, but do not quantify partial-byte reuse.

## Native app checks

A fifth temporary repository was created through the native UI. The app uploaded a synthetic folder, stopped the upload, persisted the stopped job across relaunch, and resumed to completion. Downloaded hashes matched all three expected files; an excluded log file was absent. Folder navigation and confirmed remote file deletion passed. A repeat upload restored the deleted file and reported zero bytes transferred for content already available on Hugging Face. Live stage counters appeared in the inspector.

Testing uncovered and fixed queue cancellation races, delayed repository listings after creation, and remote-table interactions that previously worked only directly over filenames. Completed uploads now show their completion time and hide potentially stale sampled stage counters.

## Cleanup and limits

All five temporary remote repositories were deleted and their absence verified. Local synthetic upload history and fixture/download directories were removed. No existing user repository was modified.

These checks do not establish multi-terabyte reliability, behavior under prolonged network outages, or quantified partial-byte deduplication. Developer ID signing, notarization, and a self-contained runtime installer remain distribution work.
