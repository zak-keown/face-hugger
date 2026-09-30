#!/usr/bin/env python3
"""Local reliability harness. No HF requests, remote repos, or network toggles.

Uses the installed HF filter implementation for scanning. Upload lifecycle cases
run the real bridge and OS subprocess/signals around a checkpoint-writing fixture,
not the HF uploader. SDK errors are injected; they do not prove outage recovery.
"""
from __future__ import annotations
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import resource
import select
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve()


def load_bridge():
    spec = importlib.util.spec_from_file_location("reliability_bridge", ROOT / "Resources/bridge.py")
    bridge = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bridge)
    return bridge


def rss_mib():
    # Darwin reports bytes; Linux reports KiB. This is process lifetime high-water.
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return round(value / (1024 ** 2 if sys.platform == "darwin" else 1024), 2)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def compare_checks(bridge):
    class Listing:
        def __init__(self): self.visited = 0
        def list_repo_tree(self, **kwargs):
            for index in range(200000):
                self.visited += 1
                yield SimpleNamespace(path=f"file-{index}")
    api = Listing()
    args = bridge.parser().parse_args(["compare", "--repo", "fixture/model", "--file", "file-0", "--file", "not-present"])
    result = bridge.compare_paths(args, api)
    require(result["paths"] == ["file-0"] and not result["complete"] and not result.get("conflicts"), "Bounded compare must not establish absence")
    require(api.visited == 100000, "Default listing cap changed")
    args.file = [f"file-{index}" for index in range(2000)]
    early = Listing()
    require(bridge.compare_paths(args, early)["complete"], "All exact matches should complete")
    require(early.visited == 2000, "Comparison must stop after all targets found")
    args.file.append("file-2000")
    rejected = Listing()
    try:
        bridge.compare_paths(args, rejected)
    except ValueError:
        pass
    else:
        raise AssertionError("More than 2000 paths accepted")
    require(rejected.visited == 0, "Oversized request must fail before listing")
    return {"listing_cap": api.visited, "partial_paths": result["paths"], "early_exit_entries": early.visited, "request_cap": 2000}


def failure_checks(bridge):
    import huggingface_hub
    original_handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT)}
    results = []
    try:
        for error in [ConnectionError("Connection reset by peer"), TimeoutError("Read timed out"),
                      PermissionError("HTTP 403 Forbidden")]:
            class API:
                def repo_info(self, **kwargs): raise error
            output = io.StringIO()
            with patch.object(huggingface_hub, "HfApi", return_value=API()), patch.object(bridge, "_PROTOCOL", output):
                code = bridge.main(["info", "--repo", "fixture/model"])
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            require(code == 1 and len(events) == 1 and events[0]["event"] == "error", "SDK failure produced a success result")
            results.append(type(error).__name__)
        class PartialAPI:
            def list_repo_tree(self, **kwargs):
                yield SimpleNamespace(path="first")
                raise TimeoutError("Read timed out after one remote page")
        args = bridge.parser().parse_args(["compare", "--repo", "fixture/model", "--file", "first", "--file", "missing"])
        try:
            bridge.compare_paths(args, PartialAPI())
        except TimeoutError:
            results.append("partial-listing-error-propagated")
        else:
            raise AssertionError("Partial network failure was misreported as a complete comparison")
    finally:
        for sig, handler in original_handlers.items(): signal.signal(sig, handler)
    return {"injected_errors": results, "real_network_requests": 0}


def cycle_worker(source, checkpoint, finish):
    import huggingface_hub
    bridge = load_bridge()
    fixture = """
import json,os,sys,time
from pathlib import Path
p=Path(sys.argv[1]); n=int(p.read_text())+1 if p.exists() else 1
pending=p.with_suffix('.pending'); pending.write_text(str(n)); pending.replace(p)
print('FIXTURE_READY '+json.dumps({'pid':os.getpid(),'checkpoint':n}),flush=True)
if sys.argv[2]!='finish':
    while True: time.sleep(1)
"""
    class API:
        def repo_info(self, **kwargs): return SimpleNamespace(id="fixture/model", private=True)
        def list_repo_tree(self, **kwargs): return iter(())
    with patch.object(huggingface_hub, "HfApi", return_value=API()), patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", fixture, checkpoint, "finish" if finish else "wait"]):
        return bridge.main(["upload", "--repo", "fixture/model", "--source", source])


def lifecycle_checks(source, checkpoint, cycles):
    durations = []
    for iteration in range(cycles + 1):
        final = iteration == cycles
        command = [sys.executable, str(SCRIPT), "--cycle-worker", str(source), str(checkpoint)]
        if final: command.append("--finish")
        env = dict(os.environ, HF_HUB_OFFLINE="1", HF_HUB_DISABLE_TELEMETRY="1")
        env.pop("HF_TOKEN", None)
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        child_pid = None
        data = b""
        started = time.monotonic()
        try:
            deadline = started + 15
            while time.monotonic() < deadline and child_pid is None:
                ready, _, _ = select.select([process.stdout], [], [], 0.25)
                if not ready: continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk: break
                data += chunk
                for line in data.splitlines():
                    try: event = json.loads(line)
                    except json.JSONDecodeError: continue
                    message = event.get("message", "")
                    if message.startswith("FIXTURE_READY "):
                        record = json.loads(message.removeprefix("FIXTURE_READY "))
                        child_pid = record["pid"]
                        require(record["checkpoint"] == iteration + 1, "Restart did not read the fixture checkpoint")
            require(child_pid is not None, "Fixture subprocess failed to become ready")
            if not final: process.send_signal(signal.SIGTERM)
            tail, errors = process.communicate(timeout=12)
            data += tail
            events = [json.loads(line) for line in data.splitlines()]
            require(process.returncode == (0 if final else 130), f"Unexpected bridge exit {process.returncode}: {errors.decode()}")
            require(any(e["event"] == "complete" for e in events) == final, "Canceled process falsely completed")
            try: os.kill(child_pid, 0)
            except ProcessLookupError: pass
            else: raise AssertionError("Upload child survived bridge termination")
            durations.append(round(time.monotonic() - started, 3))
        finally:
            if process.poll() is None:
                # Give the bridge's signal handler a chance to reap its child,
                # including failures before the READY marker was observed.
                process.terminate()
                try: process.communicate(timeout=12)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
            process.stdout.close(); process.stderr.close()
            if child_pid:
                try: os.killpg(child_pid, signal.SIGKILL)
                except ProcessLookupError: pass
    return {"stopped_cycles": cycles, "final_success": True, "fixture_checkpoint": int(checkpoint.read_text()), "cycle_seconds": durations, "scope": "Real bridge/process SIGTERM and fixture checkpoint restart; not HF upload resumption"}


def worker(mode, source):
    bridge = load_bridge()
    start = time.monotonic()
    if mode == "scan":
        args = bridge.parser().parse_args(["scan", "--source", source])
        result = bridge.scan_folder(args)
        require(result["total_count"] == 10000 and result["included_count"] == 10000, "Scan totals lost files")
        require(len(result["files"]) == 2000 and result["truncated"], "Preview row cap failed")
        require(result["included_bytes"] == 10000 * 32, "Scan byte totals incorrect")
        result = {"files": result["total_count"], "preview_rows": len(result["files"]), "bytes": result["included_bytes"]}
    elif mode == "compare": result = compare_checks(bridge)
    else: result = failure_checks(bridge)
    result.update(seconds=round(time.monotonic() - start, 3), peak_rss_mib=rss_mib())
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", choices=["scan", "compare", "failures"])
    parser.add_argument("--source", default="")
    parser.add_argument("--cycle-worker", nargs=2, metavar=("SOURCE", "CHECKPOINT"))
    parser.add_argument("--finish", action="store_true")
    parser.add_argument("--cycles", type=int, default=8)
    args = parser.parse_args()
    if args.cycle_worker: return cycle_worker(*args.cycle_worker, args.finish)
    if args.worker: worker(args.worker, args.source); return 0
    require(1 <= args.cycles <= 100, "cycles must be between 1 and 100")
    # TemporaryDirectory removes all 10,000 fixtures even on assertion failure.
    with tempfile.TemporaryDirectory(prefix="face-hugger-reliability-") as temporary:
        base = Path(temporary); source = base / "many files"; source.mkdir()
        for index in range(10000):
            folder = source / f"group-{index // 100:03d}"; folder.mkdir(exist_ok=True)
            (folder / f"file-{index:05d}.txt").write_bytes(b"x" * 32)
        report = {"python": sys.version.split()[0], "offline_harness": True}
        for mode in ["scan", "compare", "failures"]:
            completed = subprocess.run([sys.executable, str(SCRIPT), "--worker", mode, "--source", str(source)], capture_output=True, text=True, timeout=60)
            require(completed.returncode == 0, f"{mode} worker failed: {completed.stderr}")
            report[mode] = json.loads(completed.stdout)
        cycle_source = base / "cycle files"; cycle_source.mkdir(); (cycle_source / "fixture.txt").write_text("local fixture")
        report["lifecycle"] = lifecycle_checks(cycle_source, base / "checkpoint", args.cycles)
    report["temporary_fixtures_removed"] = not base.exists()
    report["limits"] = "RSS is each worker process lifetime high-water, including imports; SDK failures are injected, no real network outage or HF byte-transfer resumption tested."
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
