#!/usr/bin/env python3
"""Face Hugger's JSON-lines bridge. Tokens arrive through HF_TOKEN, never argv.

Every output line is a JSON object with `event`. Commands other than upload emit
one `result` with `data`; uploads emit `status`, `log`, recognized `progress`
counts, and finally `complete`.
Errors emit `error` and exit nonzero. SIGINT/SIGTERM stop the entire CLI process
session before the bridge exits. Rerunning an upload lets HF deduplicate content.
"""
from __future__ import annotations

import argparse
from collections import deque
import contextlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import sqlite3
import tempfile
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



_COUNT = r"(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)"
_PROGRESS = re.compile(
    rf"Uploading\.\.\. (?P<checked>{_COUNT})/(?P<total>{_COUNT}) files checked, "
    rf"(?P<uploaded>{_COUNT})/(?P<upload_total>{_COUNT}) uploaded "
    r"\((?P<transferred>[0-9]+(?:\.[0-9]+)?(?:B|kB|MB|GB|TB|PB)) transferred\), "
    rf"(?P<committed>{_COUNT}) committed in (?P<commits>[0-9]+) commit\(s\)"
    r"(?:, validating (?:100|[0-9]{1,2})%)?"
)


def parse_progress(message: str):
    """Recognize only HF 2.0's non-TTY summary; unknown versions stay logs.

    Counts are pipeline snapshots, not sequential stage completion or an overall
    percentage. upload_total is Xet files; it can differ from checked total.
    """
    match = _PROGRESS.fullmatch(_ANSI.sub("", message).strip())
    if match is None:
        return None
    values = {key: int(value.replace(",", "")) if key != "transferred" else value
              for key, value in match.groupdict().items()}
    if values["checked"] > values["total"] or values["uploaded"] > values["upload_total"] or values["committed"] > values["total"]:
        return None
    return values


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
    emit("status", message="Checking local files and filters before upload…")
    # Every start/resume validates the current source, including link boundaries.
    # This metadata check is not a snapshot; files must remain stable during upload.
    with tempfile.TemporaryDirectory(prefix="face-hugger-path-check-") as directory:
        with contextlib.closing(sqlite3.connect(str(Path(directory) / "paths.sqlite"))) as database:
            index = PathIndex(database, getattr(args, "destination", ""))
            scan_folder(args, row_limit=0, included_callback=index.add)
            database.commit()
            if _STOPPING:
                raise InterruptedError("Upload stopped.")
            # hf upload can create missing public repos. Require explicit creation.
            api.repo_info(repo_id=args.repo, repo_type=args.type)
            if index.count:
                emit("status", message="Checking remote file and folder conflicts…")
                validate_upload_paths(args, api, index)
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
        recent_logs = deque(maxlen=3)
        for line in _CHILD.stdout:
            message = redact(line.strip())
            if message:
                recent_logs.append(redact(message[-1000:]))
                emit("log", message=message[-8192:])
                if progress := parse_progress(message):
                    emit("progress", **progress)
        code = _CHILD.wait()
        if code:
            detail = " | ".join(recent_logs)[-1000:]
            raise RuntimeError(f"HF upload exited with status {code}. " + (detail or "Review the upload log and retry."))
        emit("complete", url=repo_url(args.repo, args.type))
    finally:
        stop_child()
        if _CHILD is not None and _CHILD.stdout is not None:
            _CHILD.stdout.close()
        _CHILD = None



def scan_folder(args, *, filter_objects=None, default_ignores=None, row_limit=2000, included_callback=None):
    """Read metadata only; use HF's exact folder-upload filter implementation.

    System-ignore paths never enter the preview. User-filtered files appear with
    included=False. Totals cover every candidate, even when rows are capped.
    """
    if filter_objects is None or default_ignores is None:
        from huggingface_hub.utils import filter_repo_objects, DEFAULT_IGNORE_PATTERNS
        filter_objects = filter_repo_objects
        default_ignores = DEFAULT_IGNORE_PATTERNS
    source = Path(args.source).expanduser().resolve(strict=True)
    if not source.is_dir():
        raise ValueError("Choose an existing local folder to scan.")
    files = []
    total_count = included_count = included_bytes = 0
    pending = [source]
    while pending:
        directory = pending.pop()
        try:
            with os.scandir(directory) as contents:
                children = sorted(contents, key=lambda item: item.name)
        except OSError as error:
            raise ValueError(f"Cannot read folder '{directory}': {error.strerror or error}. Check its permissions.") from error
        subdirectories = []
        for entry in children:
            path = Path(entry.path)
            relative = path.relative_to(source).as_posix()
            if not list(filter_objects([relative], ignore_patterns=default_ignores)):
                continue
            try:
                info = entry.stat(follow_symlinks=True)
                if stat.S_ISDIR(info.st_mode):
                    # Mirrors pathlib glob('**/*'): do not descend into linked directories.
                    if not entry.is_symlink():
                        subdirectories.append(path)
                    continue
                if not stat.S_ISREG(info.st_mode):
                    continue
                if entry.is_symlink() and not path.resolve(strict=True).is_relative_to(source):
                    raise ValueError(f"Linked file '{relative}' points outside the selected folder. Choose a folder without external file links.")
            except OSError as error:
                raise ValueError(f"Cannot inspect '{relative}': {error.strerror or error}. Check permissions and broken links.") from error
            included = bool(list(filter_objects([relative], allow_patterns=args.include or None,
                                                 ignore_patterns=args.exclude or None)))
            total_count += 1
            if included:
                if not os.access(path, os.R_OK):
                    raise ValueError(f"Cannot read included file '{relative}'. Check its permissions.")
                included_count += 1
                included_bytes += info.st_size
                if included_callback is not None:
                    included_callback(relative)
            if len(files) < row_limit:
                files.append({"path": relative, "size": info.st_size, "included": included})
        pending.extend(reversed(subdirectories))
    files.sort(key=lambda item: item["path"])
    return {"files": files, "included_count": included_count, "included_bytes": included_bytes,
            "total_count": total_count, "truncated": total_count > row_limit}



class PathIndex:
    """Indexed full remote targets, on disk for uncapped upload preflight."""
    def __init__(self, database, destination):
        self.database = database
        destination = remote_path(destination)
        self.prefix = destination + "/" if destination else ""
        self.count = 0
        database.execute("CREATE TABLE targets (full TEXT PRIMARY KEY, relative TEXT NOT NULL)")

    def add(self, relative):
        self.database.execute("INSERT OR IGNORE INTO targets VALUES (?, ?)", (self.prefix + relative, relative))
        self.count += 1

    def observe(self, entry, *, first_conflict_only=False):
        path = entry.path
        row = self.database.execute("SELECT relative FROM targets WHERE full = ?", (path,)).fetchone()
        exact = row[0] if row else None
        if type(entry).__name__ == "RepoFolder":
            conflicts = ([{"path": exact, "reason": f"Remote path '{path}' is a folder, but the staged path is a file."}] if exact else [])
        else:
            # '/' followed by any descendant sorts before '0'; this range uses
            # the primary-key index and avoids LIKE wildcard/Unicode ambiguity.
            query = "SELECT relative FROM targets WHERE full >= ? AND full < ? ORDER BY full"
            if first_conflict_only:
                query += " LIMIT 1"
            rows = self.database.execute(query, (path + "/", path + "0"))
            conflicts = [{"path": item[0], "reason": f"Remote path '{path}' is a file, but this upload needs it as a folder."} for item in rows]
        return exact, conflicts


def validate_upload_paths(args, api, index):
    # No entry cap: every included local path is checked against the current
    # remote tree. Remote/local changes after this check remain possible.
    for entry in api.list_repo_tree(repo_id=args.repo, repo_type=args.type, path_in_repo=None, recursive=True):
        _, conflicts = index.observe(entry, first_conflict_only=True)
        if conflicts:
            conflict = conflicts[0]
            raise ValueError(f"Cannot upload '{conflict['path']}': {conflict['reason']} Choose another destination or resolve the remote path conflict.")


def compare_paths(args, api, *, entry_limit=100000):
    """Compare names/types only; incomplete listings never prove missing paths."""
    requested = list(args.file)
    if args.manifest:
        with open(args.manifest, "r", encoding="utf-8") as manifest:
            raw = manifest.read(16 * 1024 * 1024 + 1)
        if len(raw) > 16 * 1024 * 1024:
            raise ValueError("The comparison manifest is too large.")
        paths = json.loads(raw)
        if not isinstance(paths, list) or any(not isinstance(path, str) for path in paths):
            raise ValueError("The comparison manifest must be a JSON array of relative file paths.")
        requested.extend(paths)
    if len(requested) > 2000:
        raise ValueError("Compare at most 2000 staged file paths at a time.")
    if any(not isinstance(path, str) or not path or path.startswith("/") or path.endswith("/") for path in requested):
        raise ValueError("Comparison paths must be nonempty relative file paths.")
    requested = {remote_path(path) for path in requested}
    found = set()
    conflicts = {}
    def result(complete):
        return {"paths": sorted(found), "conflicts": [{"path": path, "reason": conflicts[path]} for path in sorted(conflicts)], "complete": complete}
    if not requested:
        return result(True)
    with contextlib.closing(sqlite3.connect(":memory:")) as database:
        index = PathIndex(database, args.destination)
        for path in requested:
            index.add(path)
        # Start at repo root to detect files occupying destination ancestors.
        # A missing destination is simply absent from an existing repo tree.
        for visited, entry in enumerate(api.list_repo_tree(repo_id=args.repo, repo_type=args.type,
                                                           path_in_repo=None, recursive=True), start=1):
            exact, matches = index.observe(entry)
            if exact is not None:
                found.add(exact)
            for conflict in matches:
                conflicts[conflict["path"]] = conflict["reason"]
            if requested <= found | conflicts.keys():
                return result(True)
            if visited >= entry_limit:
                return result(False)
    return result(True)


def execute(args, api) -> None:
    if hasattr(args, "repo"):
        validate_repo(args.repo)
    if args.command == "scan":
        data = scan_folder(args)
    elif args.command == "whoami":
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
    elif args.command == "compare":
        data = compare_paths(args, api)
    elif args.command == "info":
        repo = api.repo_info(repo_id=args.repo, repo_type=args.type)
        data = {"id": repo.id, "type": args.type, "private": bool(repo.private), "url": repo_url(repo.id, args.type)}
    elif args.command == "tree":
        data = []
        path = remote_path(args.path)
        try:
            for entry in api.list_repo_tree(repo_id=args.repo, repo_type=args.type,
                                            path_in_repo=path or None, recursive=False):
                directory = type(entry).__name__ == "RepoFolder"
                data.append({"path": entry.path, "type": "directory" if directory else "file",
                             "size": 0 if directory else (getattr(entry, "size", 0) or 0)})
        except Exception as error:
            if not args.allow_missing_path or not path:
                raise
            from huggingface_hub.errors import EntryNotFoundError
            if not isinstance(error, EntryNotFoundError):
                raise
            data = []
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
    scan = commands.add_parser("scan")
    scan.add_argument("--source", required=True)
    scan.add_argument("--include", action="append", default=[])
    scan.add_argument("--exclude", action="append", default=[])
    repos = commands.add_parser("repos")
    repos.add_argument("--owner", required=True)
    for name in ("compare", "info", "tree", "create", "delete", "upload"):
        command = commands.add_parser(name)
        command.add_argument("--repo", required=True)
        command.add_argument("--type", choices=("model", "dataset"), default="model")
        if name in ("tree", "delete"):
            command.add_argument("--path", default="", required=name == "delete")
        if name == "compare":
            command.add_argument("--destination", default="")
            command.add_argument("--manifest")
            command.add_argument("--file", action="append", default=[])
        if name == "tree":
            command.add_argument("--allow-missing-path", action="store_true")
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
