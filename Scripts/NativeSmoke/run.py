#!/usr/bin/env python3
"""Credential-only development launcher. Every network request runs in Swift.
Creates one disposable private dataset, uploads synthetic data, then deletes it.
Never stores a token on disk or passes it in argv. Not part of the app bundle.
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
    raise SystemExit('No existing HF credential; no mutation performed.')
env = dict(os.environ, HF_TOKEN=value)
raise SystemExit(subprocess.run([str(Path('.build/native-smoke/probe').resolve()), '--run-live'], env=env).returncode)
