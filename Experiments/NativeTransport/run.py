#!/usr/bin/env python3
"""Credential-only launcher. All network operations run in the Swift probe.

Run with the existing managed Python and --run-live. Token values are never
printed, written to files, or passed in argv. This creates and deletes one
uniquely named private dataset and a 16 MiB synthetic fixture.
"""
import os
from pathlib import Path
import subprocess
import sys

if sys.argv[1:] != ['--run-live']:
    raise SystemExit('Explicit --run-live is required.')
from huggingface_hub import get_token
value = os.environ.get('HF_TOKEN') or get_token()
if not value:
    raise SystemExit('No existing HF credential available; no mutation performed.')
env = dict(os.environ, HF_TOKEN=value)
raise SystemExit(subprocess.run([str(Path('.build/native-transport/probe').resolve()), '--run-live'], env=env).returncode)
