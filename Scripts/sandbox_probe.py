#!/usr/bin/env python3
"""Build a signed sandbox probe against an already-staged native Python runtime.

No download, remote upload, notarization, or automatic folder selection occurs.
Launch the printed app, choose /private/tmp/face-hugger-sandbox-probe-source,
then quit and launch with `open -n APP --args --restore`. Inspect both JSON
reports in its sandbox container. This exercises a helper process, not the full
App Store application or HF upload networking.
"""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import platform

ROOT = Path(__file__).resolve().parents[1]
MAGIC = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True, help='Native arch standalone Python directory containing bin/python3')
    parser.add_argument('--identity', required=True, help='Local Apple Development signing identity hash')
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    if not (runtime / 'bin/python3').is_file():
        parser.error('runtime must contain bin/python3')
    for path in runtime.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(runtime):
            parser.error(f'Runtime contains a nonrelocatable external symlink: {path.relative_to(runtime)}')
    build = ROOT / '.build/sandbox-probe'
    app = build / 'Face Hugger Sandbox Probe.app'
    # Replace only this generated harness artifact, never the source runtime.
    if app.exists(): shutil.rmtree(app)
    executable = app / 'Contents/MacOS/SandboxProbe'
    executable.parent.mkdir(parents=True)
    resources = app / 'Contents/Resources'; resources.mkdir()
    embedded = resources / 'runtime'
    shutil.copytree(runtime, embedded, symlinks=True)
    shutil.copy2(ROOT / 'Resources/bridge.py', resources / 'bridge.py')
    info = {'CFBundleIdentifier': 'dev.zakkeown.FaceHugger.SandboxProbe', 'CFBundleName': 'Face Hugger Sandbox Probe',
            'CFBundleExecutable': 'SandboxProbe', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
            'CFBundleShortVersionString': '0.1', 'LSMinimumSystemVersion': '15.0', 'NSHighResolutionCapable': True}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('swiftc', '-parse-as-library', '-swift-version', '6', '-target', platform.machine() + '-apple-macos15.0',
        '-module-cache-path', build / 'module-cache', ROOT / 'Sources/FaceHuggerCore/FolderAccess.swift',
        ROOT / 'Scripts/SandboxProbe/main.swift', '-o', executable)
    seen = set()
    count = 0
    for path in embedded.rglob('*'):
        if not path.is_file() or path.is_symlink(): continue
        with path.open('rb') as stream:
            if stream.read(4) not in MAGIC: continue
        resolved = path.resolve()
        if resolved in seen: continue
        seen.add(resolved)
        kind = subprocess.check_output(['/usr/bin/file', '-b', str(path)], text=True)
        command = ['/usr/bin/codesign', '--force', '--sign', args.identity, '--timestamp=none', '--options', 'runtime']
        if 'executable' in kind: command += ['--entitlements', str(ROOT / 'Resources/StoreHelper.entitlements')]
        run(*command, path)
        count += 1
    run('/usr/bin/codesign', '--force', '--sign', args.identity, '--timestamp=none', '--options', 'runtime',
        '--entitlements', ROOT / 'Resources/Store.entitlements', app)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    print(f'Built and signature-verified {app}\nSigned native runtime objects: {count}')
    print('Not yet a passing sandbox test: launch, choose the dedicated fixture, quit, and relaunch with --restore.')


if __name__ == '__main__':
    main()
