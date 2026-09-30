# Apple-native transport feasibility — pinned HF 2.0.0 / Xet 1.6.0

Research only, September 30, 2026. No production changes, credential access, remote mutations, Rust installation, or runtime rebuilding were performed for this investigation. The signed staged runtime remains intact. The separate URLSession network experiment is owned by the parent task.

## Finding

Apple-native HTTP is technically plausible, but **replacing Python's transport is not sufficient to remove bundled cryptographic implementations**. The shipped Python interpreter has `_ssl` and `_hashlib` built in, and the stock Xet wheel contains its own Rust TLS dependencies. A URLSession proof is useful protocol evidence, not a ready replacement for the existing resumable large-folder pipeline.

The cleanest architecture for eliminating Python/OpenSSL and Xet's bundled TLS is an entirely native Swift client using URLSession for HTTP and Apple hashing APIs. This requires implementing and validating the Hub/LFS upload protocol and durable queue recovery. It sacrifices Xet chunk deduplication and does not automatically preserve Xet's interrupted-transfer behavior. Native feature parity is additional engineering, not a flag change.

## What the Python client factory can replace

Pinned installed `huggingface_hub/utils/_http.py:362` exposes `set_client_factory`, which returns a shared `httpx2.Client`. An `httpx2.BaseTransport` adapter can delegate requests to a signed URLSession helper. `httpx2/_client.py:690` returns an explicitly supplied transport before constructing `HTTPTransport`; this avoids creating the default TLS transport for those requests.

The adapter must handle streaming request/response bodies, response headers, redirects and authorization boundaries, cancellation, error mapping, timeouts, and concurrent calls. Let one layer own redirects rather than silently changing HTTPX behavior. Preserve the HF request hooks. Prevent proxy/mount configuration from creating unintended default HTTP transports; explicit `trust_env=False` is an option to evaluate, with the resulting system proxy policy documented. Async calls have a separate `set_async_client_factory` hook.

**Process boundary:** current `bridge.py` launches a separate `python -m huggingface_hub.cli.hf upload` process. Installing a factory only in the bridge does not install it in that CLI child. A wrapper entry point must configure the child too, or the bridge must invoke SDK upload code in the configured process. The factory also cannot intercept Xet's Rust networking.

## Xet can be disabled, but the upload behavior changes

Pinned `utils/_runtime.py:155` makes `is_xet_available()` return false when `HF_HUB_DISABLE_XET` is set. Set it before importing the SDK because constants are read at import time.

`_commit_api.py:378–432` explicitly falls back to legacy LFS when Xet is unavailable. It computes missing SHA-256 values, calls the LFS batch endpoint, and requests `basic` and `multipart` transfers. Xet is therefore **not an unavoidable protocol prerequisite** for HF 2.0's file uploads.

However, `hf_api.py:5916–5945` selects the streamed multi-commit `pipelined_upload` implementation only when Xet is available. Otherwise `upload_folder` takes the legacy **single-commit** path and warns that large folders can take time and fail. The current CLI calls `upload_folder` (`cli/upload.py:244`). Disabling Xet loses the existing pipeline's overlapping upload/commit stages, adaptive commit batches, and documented re-run recovery. It is not merely a bandwidth or deduplication tradeoff.

The package metadata also declares `hf-xet>=1.6.0,<2.0.0` as a dependency on both shipped CPU architectures. Setting the environment flag leaves the wheel installed. A distribution that omits the extension needs a deliberately managed dependency package/build, not a normal installation of the current unchanged lock.

A native queue can persist successful file/object upload and commit checkpoints and retry incomplete work. That would be newly implemented **file-level recovery**, not proof of Xet chunk-level reuse. Whether interrupted multipart pieces can be reused must be demonstrated against the actual service semantics before promising it.

## Xet has an Apple TLS path, with a feature-unification trap

Source examined: Xet release commit [`de71453d952bd8b806edaa997c72313051a49050`](https://github.com/huggingface/xet-core/tree/de71453d952bd8b806edaa997c72313051a49050), archive SHA-256 `97109eb3c5ea9b29685ef3543248f23eee204e912d716e442018c79fcbf666cc`.

- `xet_pkg/Cargo.toml` and `xet_client/Cargo.toml` default to `rustls-tls` and expose `native-tls`.
- The workspace reqwest dependency has `default-features = false`, so an appropriately exclusive native feature graph is plausible.
- `hf_xet/Cargo.toml` exposes `native-tls`, but its dependencies on `xet-pkg` and `xet-client` **do not disable dependency defaults**. Adding `--features native-tls`, even alongside root `--no-default-features`, therefore leaves their Rustls defaults enabled.
- Reqwest 0.13.2 selects its native backend when native TLS is enabled and HTTP/3 is not, but compiled Rustls/AWS-LC dependencies can remain. A backend selection change is not proof of removal from the binary.

The conceptual minimal patch to the Python binding's manifest is:

```diff
--- a/hf_xet/Cargo.toml
+++ b/hf_xet/Cargo.toml
@@
-xet-pkg = { package = "hf-xet", path = "../xet_pkg", features = ["python"] }
+xet-pkg = { package = "hf-xet", path = "../xet_pkg", default-features = false, features = ["python"] }
 xet-runtime = { path = "../xet_runtime" }
-xet-client = { path = "../xet_client" }
+xet-client = { path = "../xet_client", default-features = false }
```

Then explicitly enable the native feature and the desired existing runtime behavior flags. A future isolated validation should run, for each architecture:

```sh
cargo tree --manifest-path hf_xet/Cargo.toml --locked \
  --target aarch64-apple-darwin --no-default-features \
  --features extension-module,native-tls,no-default-cache,elevated_information_level \
  --edges normal,build --prefix none
```

Repeat for `x86_64-apple-darwin`. Inspect runtime versus build-only edges and reject any unexpected retained `rustls`, `aws-lc-*`, `ring`, `openssl`, or `openssl-sys` dependency. Build the extension, inspect linked libraries and symbols, generate a new SBOM, and run real uploads, interruption/recovery tests and sandbox signing checks. The source already propagates native TLS from `xet-pkg` to `xet-data` and `xet-client`; the two defaults above are the identified top-level leaks, not a proven complete graph result.

**Not executed:** no Cargo, Rustup, or Maturin toolchain was installed at the inspected standard locations or on PATH. At the task owner's direction, no Rust toolchain was downloaded. Therefore no successful `cargo tree`, wheel build, link audit, or no-Rustls binary claim is made.

## Native TLS really targets Apple, but is not URLSession

The exact `hf_xet/Cargo.lock` names `native-tls` **0.2.18** with SHA-256 `465500e14ea162429d264d44189adc38b199b62b1c21eea9f69e4b73cb03bbf2`. The source archive downloaded from [crates.io](https://static.crates.io/crates/native-tls/native-tls-0.2.18.crate) matched that checksum.

Its `src/lib.rs:104–110` selects `imp/security_framework.rs` for `target_vendor = "apple"`. That implementation imports `security_framework::secure_transport::{ClientBuilder, SslContext, …}`. Its Cargo manifest limits OpenSSL dependencies to non-Apple, non-Windows targets. This is an Apple **Secure Transport / Security.framework** implementation, not a URLSession implementation. It requires its own compatibility and protocol validation; it must not be described as inheriting URLSession's complete behavior.

Even a successful native TLS Xet build retains non-TLS native code such as BLAKE3/SHA-2 hashing and compression, so changing TLS does not establish that the complete product contains no cryptographic implementation. No regulatory conclusion follows from this experiment.

## Python remains the larger removal obstacle

Read-only execution of the staged interpreter with `-B` confirmed:

```text
_ssl.__spec__.origin      = built-in
_hashlib.__spec__.origin  = built-in
```

They are not removable `_ssl.so` / `_hashlib.so` files in this standalone runtime. OpenSSL 3.5.8 is part of the existing embedded build. Leaving it unused by HTTP does not remove it from distribution.

A controlled import interception that rejects `ssl`/`_ssl` failed on `from huggingface_hub import HfApi`: `hf_api.py:35` imports `httpcore2`, whose import graph requires `ssl`. This happens before configuring a custom HTTP client. Thus a Python build without OpenSSL would also require a compatible `ssl` replacement or dependency forks/lazy imports; simply deleting a module or setting a custom transport is insufficient. `_hashlib` and other bundled crypto-related components would need their own inventory and replacement analysis.

All interpreter checks used `-B`. `codesign --verify --strict --deep .build/store-runtime/UploadRuntime.bundle` passes following these checks.

## Options and proof boundaries

| Option | Feasibility | Main remaining work / limitation |
| --- | --- | --- |
| Python custom transport + stock Xet | HTTP metadata can use URLSession | Xet still uses its own networking; bundled crypto unchanged |
| Python custom transport + Xet disabled | Legacy LFS available in pinned SDK | Loses current pipeline/recovery; stock interpreter still bundles OpenSSL; installation still includes Xet unless deliberately removed |
| Python custom transport + rebuilt native-TLS Xet | Source-level native route exists | Feature graph/build unproven; Python OpenSSL remains; native Rust hashing remains |
| Rebuilt Python + compatibility forks + native-TLS Xet | Possible research direction | Broad maintenance surface; not bounded or demonstrated here |
| Swift URLSession Hub/LFS client with Apple hashing | Cleanest separation from Python/Xet libraries | Must implement multi-file commit batching, streaming, checkpoint/retry semantics, cancellation, filtering, errors and migration; no Xet deduplication parity |

A successful small multipart transfer proves server compatibility for that tested operation. It does not prove production large-folder scale, interruption recovery, authentication error handling, redirect safety, multi-day operation, or release readiness. Keep the working release unchanged until a replacement meets those acceptance criteria.
