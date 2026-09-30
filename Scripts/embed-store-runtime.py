#!/usr/bin/env python3
"""Embed a staged runtime, sign native components inside-out, and seal its bundle.

Runs during the Store target build before Xcode signs the outer app. It never
downloads tools. Stage the runtime separately using stage-store-runtime.py.
"""
import os
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    root = Path(os.environ["SRCROOT"])
    source = root / ".build/store-runtime/UploadRuntime.bundle"
    if not (source / "Contents/Info.plist").is_file():
        raise SystemExit("Missing Store runtime. Run Scripts/stage-store-runtime.py before building.")
    manifest = json.loads((source / "Contents/Resources/staging-manifest.json").read_text())
    digest = hashlib.sha256((root / "Resources/runtime-requirements.txt").read_bytes()).hexdigest()
    if manifest.get("requirementsSHA256") != digest or manifest.get("python") != "3.12.14" or manifest.get("uv") != "0.12.18":
        raise SystemExit("Staged runtime does not match current Python/tools/dependencies. Restage it before building.")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(source)], check=True)
    for arch in os.environ.get("ARCHS", "arm64 x86_64").split():
        if arch not in manifest.get("architectures", {}):
            raise SystemExit(f"Staging manifest does not contain requested architecture {arch}.")
        if not (source / f"Contents/Resources/{arch}/python/bin/python3.12").is_file():
            raise SystemExit(f"Missing staged runtime for {arch}; refusing an incomplete Store app.")
    destination = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"] / source.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY") or os.environ.get("CODE_SIGN_IDENTITY") or "-"
    helpers = root / "Resources/StoreHelper.entitlements"
    magic = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
    for path in sorted(destination.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as handle:
            native = handle.read(4) in magic
        if not native:
            continue
        command = ["/usr/bin/codesign", "--force", "--sign", identity, "--options", "runtime"]
        if identity != "-":
            command.append("--timestamp")
        # Interpreter executables inherit the containing app's sandbox; libraries do not carry entitlements.
        if path.parent.name == "bin" and path.name.startswith("python"):
            command += ["--entitlements", str(helpers)]
        subprocess.run(command + [str(path)], check=True)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", identity, str(destination)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(destination)], check=True)


if __name__ == "__main__":
    main()
