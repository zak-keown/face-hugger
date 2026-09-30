#!/usr/bin/env python3
"""Build-time, relocatable HF runtime bundle. Never touches the user's runtime.

Requires uv 0.12.18 and Apple's command-line tools. Network access occurs only
while staging Python and hash-locked binary wheels. Output is not a Store-ready
signed application: the app packager must re-sign native code with its identity
and helper entitlements, then seal this bundle and its containing app.
"""
from __future__ import annotations
import argparse
from email.parser import Parser
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PYTHON_VERSION = '3.12.14'
UV_VERSION = '0.12.18'
ARCHES = {'arm64': ('aarch64', 'aarch64-apple-darwin'), 'x86_64': ('x86_64', 'x86_64-apple-darwin')}
MACH_MAGICS = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}


def run(command, *, env=None, capture=False):
    return subprocess.run([str(part) for part in command], env=env, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def native_files(root):
    for path in root.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACH_MAGICS:
                    yield path


def audit_links(root):
    for path in root.rglob('*'):
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target) or not path.resolve().is_relative_to(root.resolve()):
                raise RuntimeError(f'Nonrelocatable link: {path.relative_to(root)} -> {target}')
            if not path.exists():
                raise RuntimeError(f'Broken runtime link: {path.relative_to(root)}')


def relocate_native(root, source, arch):
    inventory = []
    for path in native_files(root):
        # uv rewrites libpython's LC_ID_DYLIB to its installation path. It is an
        # identity, not an external dependency; restore a relocatable identity.
        if path.name == 'libpython3.12.dylib':
            run(['install_name_tool', '-id', '@rpath/libpython3.12.dylib', path])
        dependencies = run(['otool', '-L', path], capture=True).stdout.splitlines()[1:]
        for line in dependencies:
            dependency = line.strip().split(' (', 1)[0]
            if dependency.startswith(str(source) + '/'):
                target = root / Path(dependency).relative_to(source)
                replacement = '@loader_path/' + os.path.relpath(target, path.parent)
                run(['install_name_tool', '-change', dependency, replacement, path])
            elif dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise RuntimeError(f'External native dependency in {path.relative_to(root)}: {dependency}')
        # Check embedded rpaths as well as dependency names.
        commands = run(['otool', '-l', path], capture=True).stdout.splitlines()
        for index, line in enumerate(commands):
            if line.strip() == 'cmd LC_RPATH':
                value = commands[index + 2].strip().split('path ', 1)[-1].split(' (offset', 1)[0]
                if value.startswith('/'):
                    if value.startswith(str(source) + '/'):
                        target = root / Path(value).relative_to(source)
                        run(['install_name_tool', '-rpath', value, '@loader_path/' + os.path.relpath(target, path.parent), path])
                    else:
                        raise RuntimeError(f'Absolute runtime search path in {path.relative_to(root)}: {value}')
        run(['lipo', '-verify_arch', arch, path])
        # Structural staging signature only. Distribution replaces this signature.
        run(['codesign', '--force', '--sign', '-', path], capture=True)
        run(['codesign', '--verify', '--strict', path], capture=True)
        inventory.append(str(path.relative_to(root)))
    return inventory



def license_inventory(root):
    packages = []
    site = root / 'lib/python3.12/site-packages'
    for directory in sorted(site.glob('*.dist-info')):
        metadata = Parser().parsestr((directory / 'METADATA').read_text())
        notices = [str(path.relative_to(root)) for path in directory.rglob('*') if path.is_file()
                   and any(word in path.name.lower() for word in ('license', 'licence', 'copying', 'notice', 'authors', 'copyright'))]
        packages.append({'name': metadata.get('Name'), 'version': metadata.get('Version'),
                         'licenseExpression': metadata.get('License-Expression') or metadata.get('License'),
                         'licenseFiles': sorted(notices)})
    return {'packages': packages, 'pythonLicense': 'lib/python3.12/LICENSE.txt',
            'nativeComponentNoticeAudit': 'Incomplete: install-only CPython lacks the full standalone build licenses/metadata; obtain matching native component notices before distribution.'}


def validate_relocated(bundle, arches, report):
    with tempfile.TemporaryDirectory(prefix='face-hugger-runtime-relocation-') as temporary:
        moved = Path(temporary) / 'location with spaces' / 'UploadRuntime.bundle'
        shutil.copytree(bundle, moved, symlinks=True)
        for arch in arches:
            executable = moved / 'Contents/Resources' / arch / 'python/bin/python3.12'
            environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONNOUSERSITE='1', HF_HUB_DISABLE_TELEMETRY='1')
            for key in ('PYTHONHOME', 'PYTHONPATH', 'VIRTUAL_ENV', 'HF_TOKEN'):
                environment.pop(key, None)
            script = "import json,sys,ssl,sqlite3,ctypes,huggingface_hub,hf_xet,yaml; assert sys.version.startswith('3.12.14'); assert huggingface_hub.__version__=='2.0.0'; print(json.dumps({'python':sys.version.split()[0], 'prefix':sys.prefix, 'hf':huggingface_hub.__version__}))"
            try:
                output = run([executable, '-I', '-B', '-c', script], env=environment, capture=True)
                values = json.loads(output.stdout)
                if not Path(values['prefix']).resolve().is_relative_to(moved.resolve()):
                    raise RuntimeError('Python prefix did not relocate inside the bundle.')
                run([executable, '-I', '-B', '-m', 'huggingface_hub.cli.hf', 'upload', '--help'], env=environment, capture=True)
                report[arch]['execution'] = 'passed-relocated-imports-and-hf-upload-help'
            except OSError as error:
                if arch == platform.machine() or error.errno not in (8, 86):
                    raise
                report[arch]['execution'] = 'not-executed-cross-architecture'
                report[arch]['executionNote'] = f'{error.strerror} (errno {error.errno}); execute on matching hardware or Rosetta before claiming runtime support.'
        run(['codesign', '--verify', '--strict', moved], capture=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--uv', default=shutil.which('uv'))
    parser.add_argument('--arch', action='append', choices=list(ARCHES))
    parser.add_argument('--output', type=Path, default=ROOT / '.build/store-runtime/UploadRuntime.bundle')
    parser.add_argument('--replace', action='store_true', help='Replace a previously staged bundle identified by its manifest.')
    args = parser.parse_args()
    arches = list(dict.fromkeys(args.arch or ARCHES))
    if not args.uv or run([args.uv, '--version'], capture=True).stdout.split()[1] != UV_VERSION:
        raise RuntimeError(f'Install uv {UV_VERSION} or pass its --uv path.')
    lock = ROOT / 'Resources/runtime-requirements.txt'
    output = args.output.resolve()
    if output.exists() and (not args.replace or not (output / 'Contents/Resources/staging-manifest.json').is_file()):
        raise RuntimeError('Output exists. Use --replace only for a previously staged runtime bundle.')
    cache = ROOT / '.build/store-runtime-cache'
    environment = {key: value for key, value in os.environ.items() if not key.startswith('UV_') and key not in ('HF_TOKEN', 'VIRTUAL_ENV', 'PYTHONHOME', 'PYTHONPATH')}
    environment.update(UV_CACHE_DIR=str(cache / 'uv'), UV_PYTHON_INSTALL_DIR=str(cache / 'python'), UV_NO_PROGRESS='1')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='face-hugger-runtime-stage-', dir=output.parent) as temporary:
        bundle = Path(temporary) / 'UploadRuntime.bundle'
        resources = bundle / 'Contents/Resources'
        resources.mkdir(parents=True)
        info = {'CFBundleIdentifier': 'dev.zakkeown.FaceHugger.UploadRuntime', 'CFBundleName': 'UploadRuntime',
                'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '3', 'CFBundleShortVersionString': '3.12.14'}
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        report = {'format': 1, 'python': PYTHON_VERSION, 'uv': UV_VERSION,
                  'requirementsSHA256': digest(lock), 'architectures': {}, 'signing': 'ad-hoc staging only; re-sign native code and bundle for distribution'}
        for arch in arches:
            uv_arch, platform_tag = ARCHES[arch]
            identifier = f'cpython-{PYTHON_VERSION}-macos-{uv_arch}-none'
            candidates = [ROOT / '.build/runtime-check/python' / identifier, cache / 'python' / identifier]
            source = next((path for path in candidates if (path / 'bin/python3.12').is_file()), None)
            if source is None:
                run([args.uv, 'python', 'install', identifier, '--no-bin', '--no-config'], env=environment)
                source = cache / 'python' / identifier
            source = source.resolve()
            target = resources / arch / 'python'
            shutil.copytree(source, target, symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
            # Do not ship installer entrypoints or a venv referring to an external interpreter.
            site = target / 'lib/python3.12/site-packages'
            shutil.rmtree(site)
            site.mkdir()
            for path in (target / 'bin').iterdir():
                if path.name not in ('python', 'python3', 'python3.12'):
                    path.unlink()
            run([args.uv, 'pip', 'install', '--python', sys.executable, '--target', site, '--python-version', PYTHON_VERSION,
                 '--python-platform', platform_tag, '--require-hashes', '--only-binary', ':all:',
                 '--no-config', '--default-index', 'https://pypi.org/simple', '-r', lock], env=environment)
            # The app invokes the module via sys.executable; wheel entrypoint scripts
            # have build-path shebangs and are neither needed nor retained.
            if (site / 'bin').exists():
                shutil.rmtree(site / 'bin')
            audit_links(target)
            natives = relocate_native(target, source, arch)
            report['architectures'][arch] = {'nativeFiles': natives, 'pythonBuild': (source / 'BUILD').read_text().strip(), 'licenses': license_inventory(target)}
        # The manifest is inside the resource seal; execution validation will be
        # written to the final manifest, followed by re-sealing the bundle.
        manifest = resources / 'staging-manifest.json'
        manifest.write_text(json.dumps(report, indent=2) + '\n')
        shutil.copy2(lock, resources / 'runtime-requirements.txt')
        run(['codesign', '--force', '--sign', '-', bundle], capture=True)
        validate_relocated(bundle, arches, report['architectures'])
        manifest.write_text(json.dumps(report, indent=2) + '\n')
        run(['codesign', '--force', '--sign', '-', bundle], capture=True)
        run(['codesign', '--verify', '--strict', bundle], capture=True)
        if output.exists():
            shutil.rmtree(output)
        shutil.move(bundle, output)
    print(json.dumps({'bundle': str(output), 'architectures': {arch: values['execution'] for arch, values in report['architectures'].items()}}, indent=2))


if __name__ == '__main__':
    main()
