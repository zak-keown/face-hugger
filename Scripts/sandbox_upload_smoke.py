#!/usr/bin/env python3
"""Opt-in sandbox bridge → HF CLI upload, byte verification, and cleanup.

Run with the managed Python and --run-live. Credentials go only through the
signed probe's environment, never argv, disk, or logs. Select the dedicated
fixture using the native picker. No shipping application code is changed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = Path('/private/tmp/face-hugger-sandbox-probe-source')
RESULT = ROOT / '.build/sandbox-probe/live-upload-result.json'
TOKEN = ''


def clean(value):
    if isinstance(value, str):
        if TOKEN: value = value.replace(TOKEN, '[redacted]')
        return re.sub(r'hf_[A-Za-z0-9]{8,}', '[redacted]', value)
    if isinstance(value, dict): return {k: clean(v) for k, v in value.items()}
    if isinstance(value, list): return [clean(v) for v in value]
    return value


def emit(**fields):
    print(json.dumps(clean(fields)), flush=True)


def main():
    global TOKEN
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-live', action='store_true')
    parser.add_argument('--timeout', type=int, default=240)
    args = parser.parse_args()
    if not args.run_live: parser.print_help(); return 2
    from huggingface_hub import HfApi, get_token, hf_hub_download
    TOKEN = os.environ.get('HF_TOKEN') or get_token() or ''
    if not TOKEN:
        credential = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', 'dev.zakkeown.FaceHugger', '-a', 'huggingface', '-w'], capture_output=True, text=True, timeout=30)
        if credential.returncode == 0: TOKEN = credential.stdout.strip()
    if not TOKEN: raise RuntimeError('No existing HF credential; no remote mutation performed.')
    executable = ROOT / '.build/sandbox-probe/Face Hugger Sandbox Probe.app/Contents/MacOS/SandboxProbe'
    if not executable.is_file(): raise RuntimeError('Build the signed SandboxProbe first.')
    if FIXTURE.exists(): raise RuntimeError('Fixture already exists; refusing to overwrite it.')
    api = HfApi(token=TOKEN)
    owner = api.whoami()['name']
    repo = f'{owner}/face-hugger-sandbox-{uuid.uuid4().hex[:12]}'
    if api.repo_exists(repo_id=repo, repo_type='model'): raise RuntimeError('Unexpected repo collision.')
    record = {'repo': repo, 'private': True, 'passed': False, 'deleted': False, 'fixture_removed': False,
              'scope': 'Actual signed sandbox bridge → second bundled Python HF CLI upload; no stop/resume or outage test.'}
    RESULT.parent.mkdir(parents=True, exist_ok=True)
    def save(): RESULT.write_text(json.dumps(clean(record), indent=2))
    save()  # Record collision-checked intent before creation, without a credential.
    process = None
    error = None
    fixture_created = False
    try:
        FIXTURE.mkdir(mode=0o700)
        fixture_created = True
        payload = FIXTURE / 'payload'; payload.mkdir()
        files = {'notes.txt': b'Face Hugger signed sandbox upload verification.\n', 'nested/sample.bin': bytes(range(256)) * 16}
        for name, data in files.items():
            path = payload / name; path.parent.mkdir(exist_ok=True); path.write_bytes(data)
        api.create_repo(repo_id=repo, repo_type='model', private=True, exist_ok=False)
        if not api.repo_info(repo_id=repo, repo_type='model').private: raise RuntimeError('Test repo is not private.')
        env = dict(os.environ)
        env.pop('HF_TOKEN', None); env.pop('HF_HUB_OFFLINE', None)
        env['FACEHUGGER_PROBE_TOKEN'] = TOKEN; env['FACEHUGGER_PROBE_REPO'] = repo
        process = subprocess.Popen([str(executable), '--upload'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        emit(stage='awaiting-native-folder-selection', fixture=str(FIXTURE), repo=repo, probe_pid=process.pid)
        report_path = FIXTURE / 'face-hugger-upload.json'
        deadline = time.monotonic() + args.timeout
        while not report_path.exists() and time.monotonic() < deadline:
            if process.poll() is not None: raise RuntimeError('Probe exited before upload report.')
            time.sleep(0.25)
        if not report_path.exists(): raise TimeoutError('Signed probe timed out.')
        report = json.loads(report_path.read_text())
        record['probe'] = clean(report); save()
        if not report.get('passed'): raise RuntimeError('Sandbox upload failed; see sanitized report.')
        if report.get('sandbox_container') != 'dev.zakkeown.FaceHugger.SandboxProbe':
            raise RuntimeError('Expected sandbox container was not reported.')
        expected = {'sandbox-check/' + name for name in files}
        actual = set(api.list_repo_files(repo_id=repo, repo_type='model')) - {'.gitattributes'}
        if actual != expected: raise RuntimeError('Unexpected remote file set.')
        verified = []
        for name, content in files.items():
            downloaded = hf_hub_download(repo_id=repo, repo_type='model', filename='sandbox-check/' + name,
                                         token=TOKEN, local_dir=FIXTURE / 'downloads', force_download=True)
            if Path(downloaded).read_bytes() != content: raise RuntimeError('Downloaded bytes do not match.')
            verified.append({'path': 'sandbox-check/' + name, 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()})
        record['verified'] = verified; record['passed'] = True; save()
        emit(stage='sandbox-upload-and-downloaded-bytes-verified', files=len(verified))
    except BaseException as caught:
        error = caught; record['error'] = clean(str(caught)); save()
    finally:
        running = FIXTURE / 'face-hugger-upload-running.json'
        if process and process.poll() is None and not (FIXTURE / 'face-hugger-upload.json').exists() and running.exists():
            try:
                os.kill(json.loads(running.read_text())['bridge_pid'], signal.SIGTERM)
                deadline = time.monotonic() + 12
                while not (FIXTURE / 'face-hugger-upload.json').exists() and time.monotonic() < deadline: time.sleep(0.1)
            except (ProcessLookupError, FileNotFoundError): pass
        if process:
            if process.poll() is None: process.terminate()
            try: _, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); _, stderr = process.communicate()
            if stderr: record['probe_stderr_tail'] = clean(stderr.decode(errors='replace')[-2000:])
        try:
            api.delete_repo(repo_id=repo, repo_type='model', missing_ok=True)
            record['deleted'] = not api.repo_exists(repo_id=repo, repo_type='model')
            if not record['deleted']: raise RuntimeError('Private test repo still exists.')
        except Exception as cleanup:
            record['cleanup_error'] = clean(str(cleanup))
            if error is None: error = cleanup
        if fixture_created and FIXTURE.exists(): shutil.rmtree(FIXTURE)
        record['fixture_removed'] = not FIXTURE.exists(); save()
        emit(stage='cleanup', repo_deleted=record['deleted'], fixture_removed=record['fixture_removed'], report=str(RESULT))
    if error: emit(stage='failed', error=str(error)); return 1
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        emit(stage='failed', error=str(error))
        raise SystemExit(1)
