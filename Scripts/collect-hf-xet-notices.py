#!/usr/bin/env python3
"""Collect source notices for exactly the bundled HF Xet 1.6.0 SBOM union.

No crate/source code is executed. HTTPS registry records, compressed archives,
individual notice sizes, and aggregate download volume are bounded. Only regular
notice files are retained; archive paths are validated before writing.
"""
from __future__ import annotations
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tarfile
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SBOMS = ROOT / 'Resources/ThirdParty/python-packages/hf-xet-1.6.0'
DEST = ROOT / 'Resources/ThirdParty/hf-xet-dependencies'
CACHE = ROOT / '.build/hf-xet-notices'
XET_COMMIT = 'de71453d952bd8b806edaa997c72313051a49050'
# Observed primary-source archive bytes, pinned for repeatable collection.
XET_ARCHIVE_SHA256 = '97109eb3c5ea9b29685ef3543248f23eee204e912d716e442018c79fcbf666cc'
OBJC2_ARCHIVE_SHA256 = 'a6685e9b30da4c2b9ed807e8344d7248447daf1d5ab5b7af4fa3755545f96a4d'
MAX_ARCHIVE = 32 * 1024 * 1024
MAX_INDEX = 8 * 1024 * 1024
MAX_NOTICE = 4 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024
NOTICE_NAME = re.compile(r'^(?:licen[cs]e|copying|notice|authors?|copyright)(?:[._-].*)?$', re.I)
_download_bytes = 0
_lock = threading.Lock()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url, cached, limit):
    global _download_bytes
    if cached.is_file():
        data = cached.read_bytes()
        if len(data) > limit:
            raise ValueError('Cached response exceeds limit')
        return data
    request = urllib.request.Request(url, headers={'User-Agent': 'FaceHugger-notice-audit/1.0 (source-notices-only)'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                data = response.read(limit + 1)
            if len(data) > limit:
                raise ValueError(f'Response exceeds size limit: {url}')
            with _lock:
                _download_bytes += len(data)
                if _download_bytes > MAX_TOTAL:
                    raise ValueError('Aggregate source download limit exceeded')
            cached.parent.mkdir(parents=True, exist_ok=True)
            cached.write_bytes(data)
            return data
        except (OSError, TimeoutError):
            if attempt == 3:
                raise
            time.sleep(attempt + 1)


def notices(archive, prefix, destination):
    found = []
    expanded_bytes = 0
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
        for count, member in enumerate(source, start=1):
            expanded_bytes += member.size
            if count > 50000 or expanded_bytes > MAX_TOTAL:
                raise ValueError('Source archive expansion limit exceeded')
            name = PurePosixPath(member.name)
            if not name.parts or name.parts[0] != prefix or name.is_absolute() or '..' in name.parts:
                raise ValueError(f'Unsafe archive path: {member.name}')
            if not NOTICE_NAME.fullmatch(name.name):
                continue
            if not member.isfile():
                continue
            if member.size > MAX_NOTICE:
                raise ValueError(f'Oversized notice: {member.name}')
            with source.extractfile(member) as stream:
                data = stream.read(MAX_NOTICE + 1)
            if b'\0' in data:
                raise ValueError(f'Binary notice is not accepted: {member.name}')
            relative = Path(*name.parts[1:])
            path = destination / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            found.append({'path': str(path.relative_to(DEST)), 'archivePath': member.name, 'sha256': sha(data), 'bytes': len(data)})
    return sorted(found, key=lambda value: value['path'])


def index_path(name):
    if len(name) == 1: return '1/' + name
    if len(name) == 2: return '2/' + name
    if len(name) == 3: return '3/' + name[0] + '/' + name
    return name[:2] + '/' + name[2:4] + '/' + name


def registry_component(component):
    name, version = component['name'], component['version']
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name) or not re.fullmatch(r'[A-Za-z0-9.+_-]+', version):
        raise ValueError('Unexpected registry package identity')
    expected = next(value['content'] for value in component['hashes'] if value['alg'] == 'SHA-256')
    index_url = 'https://index.crates.io/' + index_path(name.lower())
    raw = fetch(index_url, CACHE / 'index' / name, MAX_INDEX)
    versions = (json.loads(line) for line in raw.splitlines() if line.strip())
    record = next(value for value in versions if value['vers'] == version)
    if record['cksum'] != expected:
        raise ValueError(f'SBOM/registry checksum mismatch: {name}@{version}')
    archive_url = f'https://static.crates.io/crates/{name}/{name}-{version}.crate'
    archive = fetch(archive_url, CACHE / 'crates' / f'{name}-{version}.crate', MAX_ARCHIVE)
    if sha(archive) != expected:
        raise ValueError(f'Archive checksum mismatch: {name}@{version}')
    destination = DEST / f'{name}-{version}'
    files = notices(archive, f'{name}-{version}', destination)
    supplemental = None
    if not files and name in {'objc2-core-foundation', 'objc2-io-kit', 'objc2-system-configuration'} and version == '0.3.2':
        # These generated framework crates omit notices. Their checksum-verified
        # source archive identifies the exact upstream revision, not a moving tag.
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
            member = source.getmember(f'{name}-{version}/.cargo_vcs_info.json')
            if not member.isfile() or member.size > MAX_NOTICE:
                raise ValueError('Invalid cargo VCS metadata')
            with source.extractfile(member) as stream:
                vcs = json.loads(stream.read(MAX_NOTICE + 1))
        commit = vcs['git']['sha1']
        if commit != '7b1abfd750a2cacaea71d6a56ecfb83cb7de560b':
            raise ValueError('Unexpected objc2 upstream commit')
        url = f'https://codeload.github.com/madsmtm/objc2/tar.gz/{commit}'
        upstream = fetch(url, CACHE / f'objc2-{commit}.tar.gz', MAX_ARCHIVE)
        if sha(upstream) != OBJC2_ARCHIVE_SHA256:
            raise ValueError('Supplemental objc2 archive checksum changed')
        files = notices(upstream, f'objc2-{commit}', destination / 'upstream')
        supplemental = {'archiveURL': url, 'archiveSHA256': sha(upstream), 'cargoVCSInfo': vcs,
                        'scope': 'All upstream workspace notices retained because generated crate omits its own notices.'}
    return {'name': name, 'version': version, 'sbomArchitectures': component['_architectures'],
            'licenses': component.get('licenses', []), 'sourceType': 'crates.io',
            'archiveURL': archive_url, 'archiveSHA256': expected, 'registryURL': index_url,
            'registryRecord': record, 'notices': files, 'supplementalSource': supplemental,
            'status': 'retained-source-notices' if files else 'unresolved-no-notice-files-in-crate'}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    components = {}
    sbom_sources = []
    workspace = []
    for path in sorted(SBOMS.glob('*cyclonedx.json')):
        raw = path.read_bytes()
        data = json.loads(raw)
        arch = path.name.split('-')[0]
        sbom_sources.append({'path': str(path.relative_to(ROOT)), 'sha256': sha(raw), 'components': len(data['components'])})
        for component in data['components'] + [data['metadata']['component']]:
            key = (component['name'], component['version'])
            if key not in components:
                components[key] = dict(component, _architectures=[])
            components[key]['_architectures'].append(arch)
    registry = []
    for component in components.values():
        if component['bom-ref'].startswith('registry+https://github.com/rust-lang/crates.io-index#'):
            registry.append(component)
        elif component['bom-ref'].startswith('path+file:') and component['version'] == '1.6.0':
            workspace.append(component)
        else:
            raise ValueError(f'Unresolved nonregistry dependency: {component["bom-ref"]}')
    report = {'format': 1, 'hfXetVersion': '1.6.0', 'sboms': sbom_sources, 'components': [],
              'scope': 'Source-supplied notice collection for the union of shipped wheel SBOMs, including build/target supersets; not a blanket legal-completeness claim.'}
    # Frozen primary upstream commit corresponding to the release tag. Its source
    # archive is read only for notices, never extracted or executed wholesale.
    url = f'https://codeload.github.com/huggingface/xet-core/tar.gz/{XET_COMMIT}'
    archive = fetch(url, CACHE / f'xet-core-{XET_COMMIT}.tar.gz', MAX_ARCHIVE)
    if sha(archive) != XET_ARCHIVE_SHA256:
        raise ValueError('Xet workspace archive checksum changed')
    files = notices(archive, f'xet-core-{XET_COMMIT}', DEST / f'xet-workspace-1.6.0')
    for component in workspace:
        report['components'].append({'name': component['name'], 'version': component['version'],
                                     'sbomArchitectures': component['_architectures'], 'licenses': component.get('licenses', []),
                                     'sourceType': 'upstream-release-workspace', 'commit': XET_COMMIT, 'tag': 'v1.6.0',
                                     'archiveURL': url, 'archiveSHA256': sha(archive), 'notices': files,
                                     'status': 'retained-release-workspace-notices' if files else 'unresolved-no-notice-files'})
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(registry_component, component): component for component in registry}
        for future in concurrent.futures.as_completed(futures):
            component = futures[future]
            try:
                report['components'].append(future.result())
            except Exception as error:
                report['components'].append({'name': component['name'], 'version': component['version'], 'status': 'unresolved-error', 'error': str(error)})
            if len(report['components']) % 25 == 0:
                print(f'Processed {len(report["components"])}/{len(components)} components', flush=True)
    report['components'].sort(key=lambda value: (value['name'], value['version']))
    report['unresolved'] = [f'{value["name"]}@{value["version"]}' for value in report['components'] if value['status'].startswith('unresolved')]
    report['registryComponents'] = len(registry)
    report['workspaceComponents'] = len(workspace)
    (DEST / 'provenance.json').write_text(json.dumps(report, indent=2) + '\n')
    report['downloadedBytesThisRun'] = _download_bytes
    print(json.dumps({key: report[key] for key in ('registryComponents', 'workspaceComponents', 'unresolved', 'downloadedBytesThisRun')}, indent=2))


if __name__ == '__main__':
    main()
