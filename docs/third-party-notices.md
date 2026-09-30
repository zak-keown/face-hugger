# Bundled-runtime notice audit

September 30, 2026. **Python native-component notices and the HF Xet SBOM source-notice collection are retained; the overall runtime notice audit is not complete.** The retained materials are in [`Resources/ThirdParty`](../Resources/ThirdParty/README.txt). The runtime staging inventory now recognizes British `LICENCE` spelling as well as author/copyright files.

## Exact Python build

The staging agent uses uv **0.12.18**, CPython **3.12.14**, and python-build-standalone **20260901** for `aarch64-apple-darwin` and `x86_64-apple-darwin`. Both installed runtimes report `BUILD=20260901`. uv's selected downloads are the `install_only_stripped` archives.

Upstream explains that install-only archives omit full-build metadata and files outside the installation directory. Its full archives provide `PYTHON.json` and license texts; the install-only selection prefers the fastest production build. For this release the matching production full builds are `pgo+lto`. See the [upstream distribution documentation](https://github.com/astral-sh/python-build-standalone/blob/main/docs/distributions.rst) and [exact release](https://github.com/astral-sh/python-build-standalone/releases/tag/20260901).

Downloaded and verified the full archives against their GitHub release asset SHA256 digests:

| Target | Full archive SHA256 |
| --- | --- |
| aarch64 macOS | `dbefa04d4107b449e17022f9c78d3eacbd37a1aa8c166c6220dbd95addf3f318` |
| x86_64 macOS | `47fdddfa61d5f76472b7fc303c38689504d1ccec430d0017c5fa8459d0d567bf` |

All **19 upstream archive license texts** were byte-identical between architectures and are retained unchanged, together with both full `PYTHON.json` files. These cover the metadata references for CPython, bzip2, Expat, libedit, libffi, liblzma, libuuid, mpdecimal, ncurses, OpenSSL, SQLite, Tcl, and zlib. Preserve the upstream superset rather than interpreting every included notice as proof of a shipped dependency. `license-coverage.json` records each extension's static/system links and license references.

Both metadata files referenced `licenses/LICENSE.zlib-ng.txt`, which was absent from both archives and the release's repository license set. The exact upstream recipe names the `python/cpython-source-deps` **zlib-ng-2.2.4** archive with SHA256 `00bbd88709bc416cb96160ab61d3e1c8f76e106799af7328d0fe434dc7dd5004`. That archive was verified and its root `LICENSE.md` retained under the referenced name. This is supplemental coverage, not a claim that macOS bundles zlib-ng: the Darwin metadata identifies system `z` links. The inspected arm64 runtime reported zlib **1.2.12**.

The runtime reported OpenSSL **3.5.8** and SQLite **3.53.1**. OpenSSL's exact release-tag `LICENSE.txt` matches the retained `LICENSE.openssl-3.txt` byte-for-byte; its `AUTHORS.md` was additionally retained. The upstream source-tree check found those two top-level notice/author files and no top-level NOTICE file. Full source URLs, hashes, and provenance are in [`provenance.json`](../Resources/ThirdParty/python-build-standalone-20260901/provenance.json).

**Validation:** all 15 distinct license paths referenced by each architecture's `PYTHON.json` now resolve locally. This checks metadata coverage, not every source file's legal obligations or the final app's resource contents.

## Locked Python wheels

Copied the wheel-supplied notice files for the **15 installed packages**, comparing the two architecture copies byte-for-byte: anyio 4.15.1, click 8.5.0, filelock 4.0.7, fsspec 2026.9.0, h11 0.16.0, hf-xet 1.6.0, httpcore2 2.13.1, httpx2 2.13.1, huggingface_hub 2.0.0, idna 3.20, packaging 26.3, PyYAML 6.0.3, tqdm 4.70.1, truststore 0.10.4, and typing_extensions 4.16.0. [`inventory.json`](../Resources/ThirdParty/python-packages/inventory.json) records original runtime paths and hashes. Original dist-info notices remain inside the runtime; pip's bootstrap packages are removed by staging.

## Outstanding before declaring a complete audit

- **hf-xet compiled dependencies:** the source-notice collection below covers every identity in both shipped SBOMs. Review applicable license obligations and any source-embedded attributions that are not separate notice files; collection coverage is not a legal-completeness conclusion.
- **Other vendored/native wheel code:** PyYAML's separate libyaml notice is now retained as described below. This targeted check does not establish exhaustive source-level attribution coverage for every native wheel.
- **Final packaging:** retain `ThirdParty` as a directory/folder resource. The build 2 installer inspection below verified this structure and original runtime notices. Rebuild to include the new libyaml materials and repeat resource verification on the replacement package. Settings exposes an open-source notices link to the repository. The staging manifest's incomplete-audit note must not be changed to a blanket complete status.
- **Changes:** recheck provenance and notices whenever Python, standalone build tag, wheel lock, architecture, or shipped runtime contents change. Build-only uv is outside this bundled-runtime notice inventory; direct-beta downloaded tools are a separate distribution inventory.

Downloaded source archives remain under `.build/third-party-notices/` for repeat inspection and are not app resources. The retained notices, metadata, and SBOMs are local preparation; this audit did not publish a new app or artifact.

## HF Xet compiled dependency source notices

Run `python3 Scripts/collect-hf-xet-notices.py` to reproduce the collection. The script reads the union of both retained wheel SBOMs: **231 exact crates.io package identities and six local Xet workspace identities**, including the root package. It retains **426 source-supplied notice files**, approximately 2.15 MB, under [`hf-xet-dependencies`](../Resources/ThirdParty/hf-xet-dependencies/provenance.json). All 237 identities have retained source notices; there are no unresolved source-notice entries in this run.

Each registry archive SHA256 must match both its SBOM checksum and the exact version's crates.io sparse-index checksum. The manifest retains registry records, source URLs, architecture membership, license expressions, original notice paths, and each retained file's SHA256. The six workspace identities use [Xet's exact v1.6.0 release commit](https://github.com/huggingface/xet-core/tree/de71453d952bd8b806edaa997c72313051a49050). The three `objc2` framework crates omit notices from their crate archives; their checksum-verified `.cargo_vcs_info.json` identifies [this exact upstream revision](https://github.com/madsmtm/objc2/tree/7b1abfd750a2cacaea71d6a56ecfb83cb7de560b), whose workspace notices are retained as a supplemental superset. These GitHub archive hashes are recorded for provenance, rather than represented as crates.io registry checksums.

The collector downloads source data only and never executes crates or build scripts. Requests, archives, expanded archive sizes, entry counts, individual notice sizes, and total download volume are bounded; four workers are used. Only regular notice files with safe relative archive paths are retained. Cache archives remain in `.build/hf-xet-notices`, outside app resources. Source notices are preserved unchanged, including nested and vendored notice files, without interpreting their presence as proof that every such subcomponent ships in the executable. This addresses the missing component-notice collection; it does not replace a review of license-specific distribution obligations.

## PyYAML native libyaml

The bundled arm64 PyYAML **6.0.3** extension reports libyaml **0.2.5** through `yaml._yaml.get_version_string()`. The Intel extension contains the same version string; Intel execution was not performed. Both Mach-O load-command inspections show only `/usr/lib/libSystem.B.dylib`. The [exact PyYAML release workflow](https://github.com/yaml/pyyaml/blob/49790e73684bebad1df05ef8d828fa12f685bffb/.github/workflows/ci.yaml) defaults to libyaml tag `0.2.5`, and its [build recipe](https://github.com/yaml/pyyaml/blob/49790e73684bebad1df05ef8d828fa12f685bffb/packaging/build/libyaml.sh) configures static linkage. This is consistent source-recipe and binary-version evidence, not an attestation of a reproducible wheel build.

Retained the separate upstream [libyaml 0.2.5 License](../Resources/ThirdParty/libyaml-0.2.5/License) from exact commit `2c891fc7a770e8ba2fec34fc6b545c672beb37e6`, reached through the annotated `0.2.5` release tag. Its copyright years differ from PyYAML's own notice, so the PyYAML wheel license is not used as a replacement. [Provenance](../Resources/ThirdParty/libyaml-0.2.5/provenance.json) records source URLs, Git blob identities, SHA256 values, and the limits of the binary checks. Only source text and metadata were fetched; no upstream build scripts ran.

## Installer resource verification

Expanded `dist/store/FaceHugger-1.0-2.pkg` read-only into a temporary inspection directory. All **475 preexisting ThirdParty files** matched the repository bytes, retaining nested paths. The original dist-info notices listed in the package inventory were verified by SHA256 at **34 paths across the two runtimes**, and both runtimes contain CPython's `lib/python3.12/LICENSE.txt`. The installer predates the new libyaml notice/provenance files and updated README/checksum index, so it must be replaced with a rebuilt package. This verification covers resource presence and byte preservation, not an exhaustive legal audit or App Store approval.
