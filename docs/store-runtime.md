# Store runtime staging

`Scripts/stage-store-runtime.py` builds a self-contained Python/Hugging Face resource bundle for the sandboxed Store app variant. It does not modify the user's installed runtime or upload anything. It does not establish App Store acceptance.

## Build

Use the pinned uv 0.12.18 executable and Apple's command-line tools:

```sh
python3 Scripts/stage-store-runtime.py
```

The default builds arm64 and x86_64. `--arch arm64` builds just that architecture. `--uv /path/to/uv` chooses the build tool. `--replace` replaces only an existing output containing this tool's staging manifest.

Python 3.12.14 comes from uv's pinned standalone download catalog. The current catalog selects standalone build `20260901`. A previously validated `.build/runtime-check/python` installation may be reused read-only; additional interpreters and wheels are cached under `.build/store-runtime-cache`. `Resources/runtime-requirements.txt` pins and hashes the dependency graph. Installs require hashes and binary wheels, disable uv configuration discovery, and explicitly target the requested architecture. Cross-architecture wheel installation uses the native build interpreter rather than executing the foreign interpreter.

## Layout and app integration

```text
.build/store-runtime/UploadRuntime.bundle/
  Contents/Info.plist
  Contents/Resources/
    staging-manifest.json
    runtime-requirements.txt
    arm64/python/bin/python3.12
    arm64/python/lib/python3.12/...
    x86_64/python/bin/python3.12
    x86_64/python/lib/python3.12/...
```

Copy the complete `UploadRuntime.bundle` into the app's `Contents/Resources`. Select the architecture-specific interpreter and invoke the bundled bridge with it. The bridge invokes HF using `sys.executable -m huggingface_hub.cli.hf`; no generated `hf` entrypoint script or externally installed CLI is needed.

The payload is a complete standalone interpreter tree, not a venv whose interpreter points outside the app. It retains the standard library, extensions, wheel metadata/licenses, and CPython's `LICENSE.txt`. Bootstrap pip and generated console entrypoint scripts are removed. Relative interpreter aliases remain inside the payload.

Set `PYTHONDONTWRITEBYTECODE=1` and `PYTHONNOUSERSITE=1` when launching it. The signed bundle must remain read-only. Runtime caches belong in the app container, not in the interpreter tree. The Store variant's credential/cache policy is separate from direct-distribution CLI-login compatibility.

## Relocation and signing checks

Staging rejects absolute, escaping, or broken symlinks. It checks every Mach-O slice with `lipo`, audits load commands and rpaths, and repairs uv's build-location-specific libpython identity. Absolute non-system native dependencies cause a build failure.

Each native binary receives an ad-hoc staging signature and is checked with `codesign --verify --strict`; the resource bundle is then sealed. It is copied to an independent temporary path containing spaces. Native-architecture validation imports Python's SSL, SQLite, ctypes, HF, Xet, and YAML modules, checks versions and relocated prefix, and invokes `hf upload --help` without network access.

These ad-hoc signatures are not distribution signatures. The app's packaging step must sign all native binaries with the app's identity, apply the sandbox/inherit entitlements to the Python helper, sign the runtime bundle, and finally sign the containing app. Do not add a library-validation exception to hide incorrect nested signing. The resource-bundle layout avoids treating dotted Python package directories as frameworks.

## Verified state and remaining gates

On the current Apple Silicon machine, both architecture payloads passed native-slice, symlink, load-command, individual signature, and resource-seal checks. The relocated arm64 interpreter passed the imports and CLI-help checks. The x86_64 payload could not execute because this host has no Rosetta (`Bad CPU type`, errno 86). This is structural Intel validation, not a claim of Intel runtime testing.

The staging manifest records Python/uv versions, the requirements-file SHA-256, native-file inventory, package names/versions/license expressions/license-file paths, and architecture-specific execution results. Standalone install-only Python does not include the complete upstream native-component notice inventory; obtain and retain matching full-build metadata/licenses before distribution. The app's third-party notice audit tracks that separately.

Signed sandbox probes now verify selected-folder access across relaunch, helper inheritance, cache writes, and real network transfers; the Store package was signed and uploaded. See [sandbox-verification.md](sandbox-verification.md). Full Store UI recovery and Intel execution remain unverified. Signing this runtime or passing the local checks does not establish App Review acceptance.
