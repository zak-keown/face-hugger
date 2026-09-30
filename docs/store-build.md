# Mac App Store build

`project-store.yml` overlays the direct app's project with a separate Store configuration: sandbox entitlements, the `STORE_BUILD` compilation condition, version 1.0/build 3, and a build phase that embeds a self-contained upload runtime. Generate it with `xcodegen generate --spec project-store.yml`; the generated `FaceHuggerStore.xcodeproj` is ignored by Git. The direct project and its downloadable runtime remain available.

## Runtime and permissions

Stage the pinned runtime with `python3 Scripts/stage-store-runtime.py`. See [store-runtime.md](store-runtime.md). The embed phase verifies its seal and matches the recorded dependency hash/Python/uv versions against the build inputs, then signs each native component and seals the runtime bundle before Xcode signs the app. Missing architecture payloads fail the build.

The app entitlements allow outbound networking and read/write access to user-selected folders. Python executables inherit the parent's sandbox; no library-validation exception is used. Source folder bookmarks are stored with queue items and pairings. Scans and uploads retain independent access until their subprocesses exit. Old path-only records can require selecting the folder again in a sandbox.

Store workers use the architecture-specific bundled Python, an app-container HF cache, a minimal environment, and Keychain credentials entered into the app. They do not import the separate shell CLI login. Python user-site packages, bytecode writes, optional HF telemetry, and HF CLI update checks are disabled. The runtime download/install flow is compiled out of the Store variant. Settings indicates tools are included and updated with the app.

## Signing and packaging

Install a Mac App Store application certificate/private key, a Mac Installer Distribution certificate/private key, and a matching Mac App Store provisioning profile. These are different from Developer ID notarization credentials. Keep private keys in Keychain, never in Git.

```sh
FACEHUGGER_STORE_APP_IDENTITY='3rd Party Mac Developer Application: Your Name (TEAMID)' \
FACEHUGGER_STORE_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: Your Name (TEAMID)' \
FACEHUGGER_STORE_PROFILE='Your installed profile name' \
FACEHUGGER_TEAM_ID='TEAMID' \
bash Scripts/package-store.sh
```

The script builds both architectures, verifies the app signature and embedded profile, signs a flat installer package, and writes its checksum in `dist/store/`. It never uploads, submits, or publishes. `Resources/ThirdParty` is preserved as a folder resource; the Settings notices link exposes the corresponding public repository files. See [third-party-notices.md](third-party-notices.md) for audit scope and remaining gaps.

The local team now has application certificate `J96CN8H3CC`, installer certificate `7HQ7WWX8TW`, and profile `6TA8PNK7KK` (name **Face Hugger Mac App Store**, UUID `a7216289-cdf0-41be-97ca-718aa5e31617`). Private keys were imported to login Keychain and temporary raw-key/CSR files removed. Public certificate/profile material is ignored under `.build/store-signing`.

## Validation scope

The Apple Development-signed sandbox probe proved selected-folder access, restoration after relaunch, and bundled Python/HF read/write with a negative pre-restoration access check. The actual Store prototype scanned the harmless fixture and showed bundled-tools Settings. See [sandbox-verification.md](sandbox-verification.md). Both direct and universal Store development builds compiled. The locked runtime ran all 56 Python tests and the core suite ran 32 Swift tests.

Intel execution is untested on this Apple Silicon Mac without Rosetta. A successful local package is not a processed App Store build or App Review acceptance. Final screenshots must come from the intended release build. Review access, owner-confirmed content rights, and App Privacy publication are complete. Export compliance, screenshots, account-level territory requirements, and final dependency-obligation review remain separate gates. The real sandboxed upload round trip also passed; its disposable repository was cleaned.
