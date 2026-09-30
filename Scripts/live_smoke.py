#!/usr/bin/env python3
"""Opt-in live HF verification, with synthetic files and finally-block cleanup.

Run with the app's managed Python:
  "$HOME/Library/Application Support/Face Hugger/runtime/bin/python3" Scripts/live_smoke.py --run-live

Creates one temporary PRIVATE model and one temporary PUBLIC dataset. Uploads
synthetic bytes only (including one random 64 MiB file), interrupts/resumes an
upload, verifies downloads, deletes a file, and deletes both repos. A persistent
/tmp ledger records every intended repo before mutation and cleanup outcomes.
Never part of default tests or CI. Requires account write permission.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / 'Resources/bridge.py'
TOKEN = ''


def safe(value):
    if isinstance(value, str):
        return value.replace(TOKEN, '[redacted]') if TOKEN else value
    if isinstance(value, dict):
        return {k: safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [safe(v) for v in value]
    return value


def report(**fields):
    print(json.dumps(safe(fields), ensure_ascii=False), flush=True)


def bridge(command, *args):
    process = subprocess.Popen([sys.executable, str(BRIDGE), command, *args],
                               env=dict(os.environ, HF_TOKEN=TOKEN), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    try:
        stdout, _ = process.communicate(timeout=600)
    except BaseException:
        process.terminate()
        try:
            process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
        raise
    events = []
    for line in stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    if process.returncode:
        errors = [e.get('message', '') for e in events if e.get('event') == 'error']
        raise RuntimeError(f'{command} failed ({process.returncode}): ' + ' | '.join(errors))
    return events


def result(events):
    return next(e['data'] for e in events if e['event'] == 'result')


def sha(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    global TOKEN
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-live', action='store_true', help='Authorize temporary public/private repo mutations and cleanup.')
    args = parser.parse_args()
    if not args.run_live:
        parser.print_help()
        return 2
    from huggingface_hub import HfApi, get_token, hf_hub_download
    TOKEN = os.environ.get('HF_TOKEN') or get_token() or ''
    if not TOKEN:
        keychain = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', 'dev.zakkeown.FaceHugger', '-a', 'huggingface', '-w'], capture_output=True, text=True, timeout=30)
        if keychain.returncode == 0:
            TOKEN = keychain.stdout.strip()
    if not TOKEN:
        raise RuntimeError('No HF token available in environment, CLI cache, or Face Hugger Keychain.')
    api = HfApi(token=TOKEN)
    owner = api.whoami()['name']
    stamp = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    run_dir = Path(tempfile.mkdtemp(prefix='face-hugger-e2e-run-', dir='/private/tmp'))
    ledger_path = run_dir / 'ledger.json'
    ledger = {'run': stamp, 'directory': str(run_dir), 'repos': [], 'checks': [], 'success': False}
    def save():
        pending = ledger_path.with_suffix('.new')
        pending.write_text(json.dumps(ledger, indent=2))
        pending.replace(ledger_path)
    def check(name, **detail):
        ledger['checks'].append({'name': name, **detail})
        save()
        report(check=name, **detail)
    save()
    report(ledger=str(ledger_path), owner=owner)
    try:
        for kind, private in [('model', True), ('dataset', False)]:
            repo_id = f'{owner}/face-hugger-e2e-{stamp}-{kind}'
            if api.repo_exists(repo_id=repo_id, repo_type=kind):
                raise RuntimeError('Unexpected temporary repository collision; refusing mutation.')
            entry = {'id': repo_id, 'type': kind, 'private': private, 'absentBeforeCreate': True, 'created': False, 'deleted': False}
            ledger['repos'].append(entry)
            save()  # Persist intent before the network mutation.
            response = result(bridge('create', '--repo', repo_id, '--type', kind, '--private', str(private).lower()))
            entry['created'] = True
            save()
            assert response['private'] == private
            assert api.repo_info(repo_id=repo_id, repo_type=kind).private == private
            check('create_visibility', repo=repo_id, private=private)
        listed = result(bridge('repos', '--owner', owner))
        assert all(any(r['id'] == entry['id'] and r['type'] == entry['type'] for r in listed) for entry in ledger['repos'])
        check('list_repositories')
        source = run_dir / 'source folder ü'
        source.mkdir()
        (source / 'weights ü').mkdir()
        (source / 'weights ü' / 'small weights.bin').write_bytes(bytes(range(256)) * 128)
        (source / 'notes.txt').write_text('Face Hugger synthetic verification.\n')
        (source / 'skip.tmp').write_text('Excluded synthetic content.\n')
        for entry in ledger['repos']:
            repo_id, kind = entry['id'], entry['type']
            common = ['--repo', repo_id, '--type', kind]
            upload_args = [*common, '--source', str(source), '--destination', 'folder with spaces/ü', '--include', '*', '--exclude', '*.tmp']
            bridge('upload', *upload_args)
            def verify(local, remote):
                downloaded = hf_hub_download(repo_id=repo_id, repo_type=kind, filename=remote, token=TOKEN,
                                             local_dir=run_dir / 'downloads' / kind, force_download=True)
                assert sha(local) == sha(downloaded), f'Hash mismatch: {remote}'
            for local in (source / 'notes.txt', source / 'weights ü' / 'small weights.bin'):
                verify(local, 'folder with spaces/ü/' + local.relative_to(source).as_posix())
            assert not api.file_exists(repo_id, 'folder with spaces/ü/skip.tmp', repo_type=kind)
            entries = result(bridge('tree', *common, '--path', 'folder with spaces/ü'))
            assert {e['path'] for e in entries} == {'folder with spaces/ü/notes.txt', 'folder with spaces/ü/weights ü'}
            check('filtered_upload_unicode_paths_hashes', repo=repo_id)
            paths_before = sorted(api.list_repo_files(repo_id, repo_type=kind))
            bridge('upload', *upload_args)
            assert sorted(api.list_repo_files(repo_id, repo_type=kind)) == paths_before
            verify(source / 'notes.txt', 'folder with spaces/ü/notes.txt')
            check('repeat_resume_unchanged', repo=repo_id)
            replacement = run_dir / ('replacement-' + kind)
            replacement.mkdir()
            (replacement / 'notes.txt').write_text('Replacement synthetic content.\n')
            bridge('upload', *common, '--source', str(replacement), '--destination', 'folder with spaces/ü')
            verify(replacement / 'notes.txt', 'folder with spaces/ü/notes.txt')
            verify(source / 'weights ü' / 'small weights.bin', 'folder with spaces/ü/weights ü/small weights.bin')
            check('replacement_preserves_unrelated_file', repo=repo_id)
            bridge('delete', *common, '--path', 'folder with spaces/ü/notes.txt')
            assert not api.file_exists(repo_id, 'folder with spaces/ü/notes.txt', repo_type=kind)
            check('delete_file', repo=repo_id)
        model = ledger['repos'][0]
        large = run_dir / 'interrupt source'
        large.mkdir()
        payload = large / 'synthetic-random.bin'
        with payload.open('wb') as target:
            for _ in range(64):
                target.write(os.urandom(1024 * 1024))
        command = [sys.executable, str(BRIDGE), 'upload', '--repo', model['id'], '--type', 'model', '--source', str(large), '--destination', 'interruption']
        proc = subprocess.Popen(command, env=dict(os.environ, HF_TOKEN=TOKEN), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = b''
        observed_worker = False
        try:
            deadline = time.monotonic() + 120
            while proc.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([proc.stdout], [], [], 1)
                if not ready:
                    continue
                log += os.read(proc.stdout.fileno(), 8192)
                for line in log.splitlines():
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get('event') == 'progress':
                        observed_worker = True
                        break
                if observed_worker:
                    proc.send_signal(signal.SIGTERM)
                    break
            stdout, _ = proc.communicate(timeout=20)
            log += stdout
            assert observed_worker, 'No actual HF upload pipeline progress observed before interruption timeout.'
            assert proc.returncode == 130, f'Unexpected stopped exit: {proc.returncode}'
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
            proc.stdout.close()
        check('real_cli_interrupted', repo=model['id'], bytes=payload.stat().st_size, observedPipelineProgress=True, partialByteReuseVerified=False)
        bridge('upload', *command[3:])
        downloaded = hf_hub_download(repo_id=model['id'], filename='interruption/synthetic-random.bin', token=TOKEN,
                                     local_dir=run_dir / 'downloads' / 'interrupted', force_download=True)
        assert sha(payload) == sha(downloaded)
        check('real_cli_resume_hash_verified', repo=model['id'], sha256=sha(payload))
        ledger['success'] = True
        save()
    finally:
        cleanup_errors = []
        for entry in ledger['repos']:
            if not entry['absentBeforeCreate']:
                continue
            try:
                api.delete_repo(repo_id=entry['id'], repo_type=entry['type'], missing_ok=True)
                assert not api.repo_exists(repo_id=entry['id'], repo_type=entry['type'])
                entry['deleted'] = True
                save()
                report(cleanup='deleted_and_verified', repo=entry['id'])
            except Exception as error:
                entry['cleanupError'] = safe(str(error))
                cleanup_errors.append(entry['id'])
                save()
        report(success=ledger['success'], ledger=str(ledger_path), cleanupErrors=cleanup_errors)
        if cleanup_errors:
            raise RuntimeError('Cleanup needs attention; consult the ledger: ' + str(ledger_path))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        report(error=str(error))
        sys.exit(1)
