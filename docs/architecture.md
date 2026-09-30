# Architecture

Face Hugger is a macOS 15+ SwiftUI app with a small Python bridge to the official Hugging Face runtime. The first release keeps process ownership inside the app: closing a window preserves work, while quitting stops the upload before the app exits.

## Components

| Component | Responsibility |
| --- | --- |
| `Sources/FaceHugger` | SwiftUI interface, account state, queue scheduling, menu bar, notifications, sleep activity, subprocess execution |
| `Sources/FaceHuggerCore` | Codable job/repository models, input validation, atomic queue persistence and interrupted-job recovery |
| `Resources/bridge.py` | JSONL protocol, HF SDK repository operations, CLI upload process supervision |
| `requirements.txt` | Pin for the managed Hugging Face runtime |
| `Resources/Assets.xcassets` | Native app icon and mascot |
| `Tests/FaceHuggerCoreTests` | Swift core behavior tests |
| `TestsPython` | Mocked bridge behavior and real local subprocess cancellation tests |

The Swift package builds the independently testable core. XcodeGen’s `project.yml` builds the macOS application, including the Swift core sources, Python bridge, requirements, and asset catalog.

## Runtime and credentials

Setup locates `uv`, creates an isolated Python 3.12 environment, and installs the pinned requirements. The app uses `~/Library/Application Support/Face Hugger/runtime/bin/python3`. A readiness marker is written after successful setup; an incomplete environment is not considered ready.

The app stores its optional token in the macOS Keychain under service `dev.zakkeown.FaceHugger`, account `huggingface`. It passes that token in `HF_TOKEN`, never as a command-line argument or in the queue archive. With no app token, Hugging Face can use the existing CLI login. Removing the saved app account only removes the app’s Keychain item.

Both the Swift subprocess reader and the bridge redact tokens from displayed output. HF telemetry is disabled for app-launched processes. No upload content or credentials are sent through another application service.

## Queue lifecycle

`AppModel` owns the queue on the main actor. `QueueArchive` writes JSON atomically to `~/Library/Application Support/Face Hugger/queue.json`.

Jobs contain a local folder path, repository identity/type, remote destination, filters, timestamps, state, and last status message. There are no file snapshots or credentials in the archive. On load, a saved `running` job becomes `interrupted`; other states remain intact. The queue is paused on launch.

Only one upload runs at a time. Success advances to the next queued job. A failure pauses the queue. Stop requests terminate the current bridge process and keep the queue paused. Resume moves the job back to the queue and invokes the same upload command against the current contents of its source folder.

The app holds a process activity to prevent idle system sleep when enabled. This does not permit uploading during system sleep or after explicit application termination. Notification permission is requested when starting an upload.

## Bridge protocol

Each command starts a separate bridge process:

```text
python3 bridge.py whoami
python3 bridge.py repos --owner OWNER
python3 bridge.py tree --repo OWNER/NAME --type model|dataset --path PATH
python3 bridge.py create --repo OWNER/NAME --type model|dataset --private true|false
python3 bridge.py delete --repo OWNER/NAME --type model|dataset --path FILE
python3 bridge.py upload --repo OWNER/NAME --type model|dataset \
  --source FOLDER --destination PATH [--include GLOB] [--exclude GLOB]
```

`--include` and `--exclude` repeat. The bridge uses argument arrays without a shell. Repository IDs require an explicit owner, and remote paths reject traversal components.

Standard output contains JSON objects, one per line:

| Event | Fields | Meaning |
| --- | --- | --- |
| `result` | `data` | Successful SDK command result |
| `status` | `message` | Upload activity description |
| `log` | `message` | Redacted output from the upload CLI |
| `complete` | `url` | Upload CLI exited successfully |
| `error` | `message` | Command failed or was interrupted |

Non-upload result shapes:

- Identity: `{name, fullName, avatarUrl, organizations: [String]}`.
- Repositories: `[{id, type, private, url}]`.
- Tree: `[{path, type: "file" | "directory", size}]`.
- Creation: `{id, type, private, url}`.
- Deletion: `{path}`.

Unexpected SDK output is redirected to standard error. Swift captures output and displays relevant errors/logs. The app retains only a bounded recent log; logs are not persisted.

## Upload execution and stopping

Repository listing and management use `HfApi`. Uploads run the official CLI through the same managed Python interpreter:

```text
python3 -m huggingface_hub.cli.hf upload OWNER/NAME SOURCE DESTINATION --repo-type TYPE
```

The bridge checks that the destination repository exists before launching the CLI. This prevents `hf upload` from implicitly creating a public repository. New repositories go through the separate creation flow with explicit visibility.

The CLI child gets its own process session. SIGINT/SIGTERM delivered to the bridge is forwarded to that process group, and the bridge waits for the child. After eight seconds it escalates to SIGKILL and reaps the child. Cancellation during process creation is deferred until the child handle is available, preventing an orphaned upload in that narrow race.

Stopping is not rollback. HF may already have committed some files. Rerunning uses HF’s resumable, deduplicating pipeline. The app does not infer precise byte progress or separate sequential phases from unstructured CLI logs.

The app’s quit delegate waits for its active job to finish stopping before replying to the termination request. There is no launch agent in this version.

## Validation and release boundary

Swift tests exercise validation and queue persistence/recovery. Python tests exercise protocol output, filtering arguments, path validation, explicit creation visibility, token redaction, missing-repo checks, successful/failed CLI exits, and signal delivery to actual local subprocesses. They require no network or credentials.

The SDK/CLI integration was additionally checked against the pinned runtime and an anonymous, read-only public repository listing. No automated authenticated upload, delete, or create is performed.

CI also builds the application with ad-hoc signing. This is build verification, not a distribution release: signing with a Developer ID, notarization, a bundled or more self-contained runtime installer, and broader authenticated end-to-end testing remain release work.
