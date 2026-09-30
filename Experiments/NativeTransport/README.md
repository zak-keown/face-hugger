# Apple-native upload feasibility

September 30, 2026. **The native transport proof passed. The shipping app is unchanged.**

`Probe.swift` imports only Foundation and CryptoKit. All test network operations use Apple URLSession: authenticated identity, private dataset creation, LFS batch negotiation, multipart upload, commit, download, repeat-object lookup and repository deletion. `otool -L` shows Apple system frameworks/Swift libraries; no Python, OpenSSL or Xet libraries are linked into the transfer executable.

## Observed result

Two independent live runs uploaded unique 16 MiB synthetic files as two multipart requests, committed them alongside a small README, downloaded the payload to disk, and matched its SHA-256. The final run also strictly verified that the server returned the matching completed object without new upload actions. Both temporary private repositories and local fixtures were deleted. The final sanitized report is [result.json](result.json).

This demonstrates **native HF/LFS compatibility**, including multipart completion, authenticated download redirects, and completed-file deduplication. It does not demonstrate interrupted-part reuse, durable queue recovery, outage handling, concurrent uploads, large-folder performance, sandbox integration, or Intel execution. No multi-terabyte test was attempted.

The payload generator/hash/part copy use 1 MiB chunks. URLSession uploads from files and downloads to a file. At most one part is staged beside the original payload. This is a bounded data path, not a measured peak-memory benchmark.

## Reproduce (explicit live mutations)

```sh
mkdir -p .build/native-transport
swiftc -parse-as-library Experiments/NativeTransport/Probe.swift -o .build/native-transport/probe
.build/runtime-check/runtime-v3/bin/python3 -B Experiments/NativeTransport/run.py --run-live
```

The Python launcher only retrieves an existing HF token and passes it in the subprocess environment; it makes no network calls and is not a proposed shipping dependency. It never prints/persists the token or puts it in argv. The executable refuses HTTP URLs and only adds the bearer token for huggingface.co; the redirect delegate strips it for other hosts. Server-supplied signed storage URLs are not logged. Normal OS certificate validation remains enabled.

A token able to create/delete the disposable private dataset is required. The retained App Review repository/token is not modified. The report records the unique test repository before creation and any cleanup failure; investigate that ledger if a run is interrupted. This is a small experiment with assertions and bounded input, not a reusable production transport.

## Decision

Proceed toward a native Swift backend using URLSession and Apple hashing. Reusing the current Python runtime with a custom HTTP adapter does not remove its statically embedded OpenSSL. A native-TLS Xet rebuild also leaves the Python problem and adds dependency-fork maintenance. See [pinned-source research](research.md).

The native LFS route gives up Xet chunk-level deduplication and the CLI's existing adaptive upload/commit pipeline. Completed whole-file reuse was proven; reliable scheduling and restart behavior need new implementation. Do not silently replace the backend with a single-commit folder upload.

## Gates before switching the app

1. Isolate native Hub API and LFS multipart transport, with bounded response sizes, explicit auth/redirect rules and file mutation detection.
2. Persist source identity, object hash, uploaded/committed state and batch boundaries. Prove stop/relaunch/retry behavior with controlled interruptions; only claim multipart continuation if demonstrated.
3. Preserve current filtering, folder bookmarks, queue semantics, destination checks, conflict warnings and repo-management behavior. Use small fixtures and bounded transfers for tests.
4. Exercise the signed sandbox, real failure paths and both supported architectures. Compare behavior against the working CLI backend.
5. Remove the Python/Xet runtime and its resources from the native Store build, audit the final binary/dependency inventory, then revisit Apple's encryption answers for that new build. Build 3 still contains third-party crypto and its current declaration must not be falsified.

The owner chose this investigation instead of pursuing the French filing. Filing drafts remain historical preparation for build 3; nothing was sent to ANSSI or App Review.
