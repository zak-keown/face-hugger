#!/usr/bin/env python3
"""Face Hugger's JSON-lines bridge. Tokens arrive through HF_TOKEN, never argv.

Every output line is a JSON object with `event`. Commands other than upload emit
one `result` with `data`; uploads emit `status`, `log`, and finally `complete`.
Errors emit `error` and exit nonzero. SIGINT/SIGTERM stop the entire CLI process
session before the bridge exits. Rerunning an upload lets HF deduplicate content.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from urllib.parse import quote

_PROTOCOL = sys.stdout
_CHILD = None
_STOPPING = False
_SPAWNING = False
_ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def redact(value: str) -> str:
    token = os.environ.get("HF_TOKEN", "")
    if token:
        value = value.replace(token, "[redacted]")
    value = re.sub(r"hf_[A-Za-z0-9]{8,}", "[redacted]", value)
    return _ANSI.sub("", value)


def emit(event: str, **fields) -> None:
    def clean(value):
        if isinstance(value, str):
            return redact(value)
        if isinstance(value, dict):
            return {key: clean(item) for key, item in value.items()}
        if isinstance(value, list):
            return [clean(item) for item in value]
        return value
    print(json.dumps(clean({"event": event, **fields}), ensure_ascii=False), file=_PROTOCOL, flush=True)


def repo_url(repo: str, kind: str) -> str:
    return "https://huggingface.co/" + ("datasets/" if kind == "dataset" else "") + quote(repo, safe="/")


def remote_path(value: str) -> str:
    value = value.strip("/")
    if any(part in (".", "..") for part in value.split("/")) or "\\" in value or "\x00" in value:
        raise ValueError("Use a repository-relative path without '.' or '..' components.")
    return value


def validate_repo(repo: str) -> None:
    # Require an explicit owner; prohibit URLs, options and implicit destinations.
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*", repo):
        raise ValueError("Repository must have the form owner/name.")


def upload_command(args) -> list[str]:
    source = Path(args.source).expanduser().resolve(strict=True)
    if not source.is_dir():
        raise ValueError("Select a local folder to upload.")
    destination = remote_path(args.destination)
    command = [sys.executable, "-m", "huggingface_hub.cli.hf", "upload", args.repo,
               str(source), destination or ".", "--repo-type", args.type]
    for pattern in args.include:
        command.extend(["--include", pattern])
    for pattern in args.exclude:
        command.extend(["--exclude", pattern])
    return command


def stop_child(signum=signal.SIGTERM) -> None:
    child = _CHILD
    if child is None or child.poll() is not None:
        return
    try:
        os.killpg(child.pid, signum)
    except ProcessLookupError:
        return
    try:
        child.wait(timeout=8)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()


def handle_signal(signum, frame) -> None:
    global _STOPPING
    if _STOPPING:
        return
    _STOPPING = True
    if _SPAWNING:
        # Popen may already have forked but not yet returned its handle. Defer
        # cancellation until the parent can reap that child.
        return
    stop_child(signum)
    raise InterruptedError("Upload stopped. Files already committed remain in the repository; resume to continue.")


def upload(args, api) -> None:
    global _CHILD, _SPAWNING
    command = upload_command(args)
    # hf upload can create missing public repos. Require an existing destination;
    # new repos must go through the app's explicit create/visibility flow.
    api.repo_info(repo_id=args.repo, repo_type=args.type)
    emit("status", message="Starting HF upload. Preparing, transferring and committing may overlap.")
    environment = dict(os.environ, PYTHONUNBUFFERED="1", NO_COLOR="1", HF_HUB_DISABLE_TELEMETRY="1")
    try:
        _SPAWNING = True
        try:
            _CHILD = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, encoding="utf-8", errors="replace", env=environment,
                                      start_new_session=True, bufsize=1)
        finally:
            _SPAWNING = False
        if _STOPPING:
            stop_child()
            raise InterruptedError("Upload stopped.")
        for line in _CHILD.stdout:
            message = line.strip()
            if message:
                emit("log", message=message[-8192:])
        code = _CHILD.wait()
        if code:
            raise RuntimeError(f"HF upload exited with status {code}. Review the upload log and retry.")
        emit("complete", url=repo_url(args.repo, args.type))
    finally:
        stop_child()
        if _CHILD is not None and _CHILD.stdout is not None:
            _CHILD.stdout.close()
        _CHILD = None


def execute(args, api) -> None:
    if hasattr(args, "repo"):
        validate_repo(args.repo)
    if args.command == "whoami":
        user = api.whoami()
        data = {"name": user["name"], "fullName": user.get("fullname", ""),
                "avatarUrl": user.get("avatarUrl", ""),
                "organizations": [org["name"] for org in user.get("orgs", [])]}
    elif args.command == "repos":
        data = []
        for kind, listing in (("model", api.list_models), ("dataset", api.list_datasets)):
            for repo in listing(author=args.owner):
                data.append({"id": repo.id, "type": kind, "private": bool(repo.private),
                             "url": repo_url(repo.id, kind)})
        data.sort(key=lambda item: item["id"].lower())
    elif args.command == "tree":
        data = []
        for entry in api.list_repo_tree(repo_id=args.repo, repo_type=args.type,
                                        path_in_repo=remote_path(args.path) or None, recursive=False):
            directory = type(entry).__name__ == "RepoFolder"
            data.append({"path": entry.path, "type": "directory" if directory else "file",
                         "size": 0 if directory else (getattr(entry, "size", 0) or 0)})
        data.sort(key=lambda item: (item["type"] != "directory", item["path"].lower()))
    elif args.command == "create":
        url = api.create_repo(repo_id=args.repo, repo_type=args.type, private=args.private == "true", exist_ok=False)
        data = {"id": args.repo, "type": args.type, "private": args.private == "true", "url": str(url)}
    elif args.command == "delete":
        path = remote_path(args.path)
        if not path:
            raise ValueError("Choose a file to delete.")
        api.delete_file(repo_id=args.repo, repo_type=args.type, path_in_repo=path,
                        commit_message=f"Delete {path} via Face Hugger")
        data = {"path": path}
    elif args.command == "upload":
        upload(args, api)
        return
    emit("result", data=data)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("whoami")
    repos = commands.add_parser("repos")
    repos.add_argument("--owner", required=True)
    for name in ("tree", "create", "delete", "upload"):
        command = commands.add_parser(name)
        command.add_argument("--repo", required=True)
        command.add_argument("--type", choices=("model", "dataset"), default="model")
        if name in ("tree", "delete"):
            command.add_argument("--path", default="", required=name == "delete")
        if name == "create":
            command.add_argument("--private", choices=("true", "false"), required=True)
        if name == "upload":
            command.add_argument("--source", required=True)
            command.add_argument("--destination", default="")
            command.add_argument("--include", action="append", default=[])
            command.add_argument("--exclude", action="append", default=[])
    return result


def main(argv=None) -> int:
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    try:
        args = parser().parse_args(argv)
        with contextlib.redirect_stdout(sys.stderr):
            from huggingface_hub import HfApi
            api = HfApi(token=os.environ.get("HF_TOKEN") or None)
            execute(args, api)
        return 0
    except (Exception, KeyboardInterrupt) as error:
        emit("error", message=str(error) or "Operation interrupted.")
        return 130 if isinstance(error, (InterruptedError, KeyboardInterrupt)) else 1


if __name__ == "__main__":
    sys.exit(main())
