import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).parents[1] / "Resources" / "bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.protocol = patch.object(bridge, "_PROTOCOL", self.output)
        self.protocol.start()
        self.addCleanup(self.protocol.stop)
        bridge._STOPPING = False
        bridge._CHILD = None
        # Scanner behavior is exercised against real folders in test_scan.py.
        self.scan_patch = patch.object(bridge, "scan_folder", return_value={"included_count": 1})
        self.scanner = self.scan_patch.start()
        self.addCleanup(self.scan_patch.stop)

    def events(self):
        return [json.loads(line) for line in self.output.getvalue().splitlines()]

    def test_whoami_contract_excludes_auth_material(self):
        api = Mock()
        api.whoami.return_value = {"name": "alice", "fullname": "Alice", "orgs": [{"name": "lab"}], "auth": {"token": "secret"}}
        bridge.execute(bridge.parser().parse_args(["whoami"]), api)
        self.assertEqual(self.events(), [{"event": "result", "data": {"name": "alice", "fullName": "Alice", "avatarUrl": "", "organizations": ["lab"]}}])

    def test_upload_command_preserves_spaces_and_patterns_without_shell(self):
        with tempfile.TemporaryDirectory(prefix="folder with spaces ") as source:
            args = bridge.parser().parse_args(["upload", "--repo", "alice/model", "--source", source,
                                               "--include", "*.safetensors", "--include", "**/*.json", "--exclude", ".git/*"])
            command = bridge.upload_command(args)
            self.assertIn(str(Path(source).resolve()), command)
            self.assertEqual(command[-6:], ["--include", "*.safetensors", "--include", "**/*.json", "--exclude", ".git/*"])
            self.assertNotIn("--token", command)
            self.assertIn(".", command)

    def test_destination_rejects_traversal(self):
        for value in ("../secret", "data/../secret", "data\\secret"):
            with self.assertRaises(ValueError):
                bridge.remote_path(value)
        self.assertEqual(bridge.remote_path("/weights/"), "weights")

    def test_repo_requires_owner(self):
        for value in ("repo", "https://huggingface.co/alice/repo", "--private", "alice/repo/extra"):
            with self.assertRaises(ValueError):
                bridge.validate_repo(value)
        bridge.validate_repo("alice/my-model")

    def test_upload_emits_success_only_after_child_success_and_redacts_logs(self):
        args = SimpleNamespace(repo="alice/model", type="model")
        script = "import sys; print('Uploading hf_abcdefghijklmnop'); print('committing', file=sys.stderr)"
        with patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", script]):
            bridge.upload(args, Mock())
        events = self.events()
        self.assertEqual(events[-1], {"event": "complete", "url": "https://huggingface.co/alice/model"})
        self.assertNotIn("hf_abcdefghijklmnop", self.output.getvalue())
        self.assertTrue(any("committing" in e.get("message", "") for e in events))

    def test_upload_failure_cannot_emit_complete(self):
        with patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", "raise SystemExit(9)"]):
            with self.assertRaisesRegex(RuntimeError, "status 9"):
                bridge.upload(SimpleNamespace(repo="alice/model", type="model"), Mock())
        self.assertFalse(any(e["event"] == "complete" for e in self.events()))

    def test_cli_failure_keeps_bounded_redacted_tail_for_recovery(self):
        script = "print('first line ignored'); print('Network timeout with hf_abcdefghijklmnop'); print('401 Unauthorized'); print('Retry connection'); raise SystemExit(1)"
        with patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", script]):
            with self.assertRaises(RuntimeError) as caught:
                bridge.upload(SimpleNamespace(repo="alice/model", type="model"), Mock())
        message = str(caught.exception)
        self.assertIn('Network timeout', message)
        self.assertIn('401 Unauthorized', message)
        self.assertIn('[redacted]', message)
        self.assertNotIn('hf_abcdefghijklmnop', message)
        self.assertNotIn('first line ignored', message)
        self.assertLessEqual(len(message), 1050)

    def test_upload_preflight_failure_never_checks_repo_or_launches_cli(self):
        self.scanner.side_effect = ValueError("Linked file points outside selected folder")
        api = Mock()
        args = SimpleNamespace(repo="alice/model", type="model")
        with patch.object(bridge, "upload_command", return_value=["unused"]), patch.object(bridge.subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(ValueError, "outside"):
                bridge.upload(args, api)
            self.scanner.assert_called_once_with(args, row_limit=0)
            api.repo_info.assert_not_called()
            spawn.assert_not_called()

    def test_missing_repository_does_not_launch_cli(self):
        api = Mock()
        api.repo_info.side_effect = RuntimeError("not found")
        with patch.object(bridge, "upload_command", return_value=["unused"]), patch.object(bridge.subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(RuntimeError, "not found"):
                bridge.upload(SimpleNamespace(repo="alice/model", type="model"), api)
            spawn.assert_not_called()

    def test_stop_reaps_cli_process(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True)
        bridge._CHILD = child
        try:
            bridge.stop_child()
            self.assertIsNotNone(child.poll())
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            bridge._CHILD = None

    def test_stop_during_spawn_reaps_child_before_handle_assignment(self):
        real_popen = subprocess.Popen
        children = []
        def interrupted_spawn(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            children.append(child)
            bridge.handle_signal(signal.SIGTERM, None)
            return child
        with patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", "import time; time.sleep(60)"]), patch.object(bridge.subprocess, "Popen", side_effect=interrupted_spawn):
            with self.assertRaises(InterruptedError):
                bridge.upload(SimpleNamespace(repo="alice/model", type="model"), Mock())
        self.assertIsNotNone(children[0].poll())
        self.assertFalse(any(e["event"] == "complete" for e in self.events()))

    def test_sigterm_bridge_reaps_real_upload_child(self):
        # Exercise actual OS signal delivery to the bridge, not just stop_child().
        child_script = "import os,time; print('READY ' + str(os.getpid()), flush=True); time.sleep(60)"
        bridge_path = str(Path(bridge.__file__).resolve())
        wrapper = f"""
import importlib.util, sys, types
from unittest.mock import Mock
spec = importlib.util.spec_from_file_location('bridge', {bridge_path!r})
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
sys.modules['huggingface_hub'] = types.SimpleNamespace(HfApi=Mock(return_value=Mock()))
bridge.upload_command = lambda args: [sys.executable, '-c', {child_script!r}]
bridge.scan_folder = lambda *args, **kwargs: {{}}
sys.exit(bridge.main(['upload', '--repo', 'alice/model', '--source', '/tmp']))
"""
        process = subprocess.Popen([sys.executable, "-c", wrapper], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        child_pid = None
        try:
            # Read raw bytes so select() reflects all buffered protocol output.
            data = b""
            for _ in range(10):
                ready, _, _ = select.select([process.stdout], [], [], 1)
                if not ready:
                    continue
                data += os.read(process.stdout.fileno(), 4096)
                for line in data.splitlines():
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get("message", "").startswith("READY "):
                        child_pid = int(event["message"].split()[1])
                if child_pid:
                    break
            self.assertIsNotNone(child_pid, data.decode())
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=12)
            self.assertEqual(process.returncode, 130, stderr.decode())
            self.assertIn(b'"event": "error"', stdout)
            with self.assertRaises(ProcessLookupError):
                os.kill(child_pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()
            if child_pid:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_tree_iterates_and_sorts_folders_before_files(self):
        folder_type = type("RepoFolder", (), {})
        folder = folder_type()
        folder.path = "weights"
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path="README.md", size=42), folder])
        bridge.execute(bridge.parser().parse_args(["tree", "--repo", "alice/model"]), api)
        self.assertEqual(self.events()[0]["data"], [{"path": "weights", "type": "directory", "size": 0}, {"path": "README.md", "type": "file", "size": 42}])

    def test_actual_hf_progress_summary(self):
        self.assertEqual(bridge.parse_progress("Uploading... 3/3 files checked, 0/1 uploaded (0.00B transferred), 0 committed in 0 commit(s)"),
                         {"checked": 3, "total": 3, "uploaded": 0, "upload_total": 1, "transferred": "0.00B", "committed": 0, "commits": 0})

    def test_progress_large_counts_and_validation_suffix(self):
        self.assertEqual(bridge.parse_progress("Uploading... 1,203/2,000 files checked, 400/603 uploaded (3.80GB transferred), 1,000 committed in 4 commit(s), validating 86%"),
                         {"checked": 1203, "total": 2000, "uploaded": 400, "upload_total": 603, "transferred": "3.80GB", "committed": 1000, "commits": 4})

    def test_unknown_or_inconsistent_progress_is_not_interpreted(self):
        for message in ("Install the HF skill", "Uploading... 3 files done", "Uploading... 3/2 files checked, 0/1 uploaded (0.00B transferred), 0 committed in 0 commit(s)",
                        "Uploading... 3/3 files checked, 2/1 uploaded (0.00B transferred), 0 committed in 0 commit(s)",
                        "Uploading... 3/3 files checked, 0/1 uploaded (0.00B transferred), 0 committed in 0 commit(s) unknown format", "Uploading… 3/3 files checked"):
            self.assertIsNone(bridge.parse_progress(message), message)

    def test_known_progress_emits_counts_and_retains_original_log(self):
        summary = "Uploading... 3/3 files checked, 1/1 uploaded (32.8kB transferred), 3 committed in 1 commit(s)"
        script = "print(" + repr(summary) + "); print('Unknown future progress format')"
        with patch.object(bridge, "upload_command", return_value=[sys.executable, "-c", script]):
            bridge.upload(SimpleNamespace(repo="alice/model", type="model"), Mock())
        events = self.events()
        self.assertEqual(sum(e["event"] == "progress" for e in events), 1)
        self.assertEqual([e["message"] for e in events if e["event"] == "log"], [summary, "Unknown future progress format"])

    def test_allow_missing_tree_only_swallows_missing_nonroot_entry(self):
        class EntryNotFoundError(Exception):
            pass
        class RepositoryNotFoundError(Exception):
            pass
        error_module = SimpleNamespace(EntryNotFoundError=EntryNotFoundError)
        arguments = ["tree", "--repo", "alice/model", "--path", "new/destination", "--allow-missing-path"]
        for error in (RepositoryNotFoundError("missing repo"), PermissionError("forbidden"), ConnectionError("offline")):
            api = Mock()
            api.list_repo_tree.side_effect = error
            with patch.dict(sys.modules, {"huggingface_hub.errors": error_module}):
                with self.assertRaises(type(error)):
                    bridge.execute(bridge.parser().parse_args(arguments), api)
        api = Mock()
        api.list_repo_tree.side_effect = EntryNotFoundError("missing folder")
        with patch.dict(sys.modules, {"huggingface_hub.errors": error_module}):
            bridge.execute(bridge.parser().parse_args(arguments), api)
        self.assertEqual(self.events(), [{"event": "result", "data": []}])
        for args in (["tree", "--repo", "alice/model", "--allow-missing-path"], arguments[:-1]):
            with self.assertRaises(EntryNotFoundError):
                bridge.execute(bridge.parser().parse_args(args), api)

    def test_allow_missing_tree_handles_lazy_generator_error(self):
        class EntryNotFoundError(Exception):
            pass
        def missing():
            raise EntryNotFoundError("not here")
            yield
        api = Mock()
        api.list_repo_tree.return_value = missing()
        with patch.dict(sys.modules, {"huggingface_hub.errors": SimpleNamespace(EntryNotFoundError=EntryNotFoundError)}):
            bridge.execute(bridge.parser().parse_args(["tree", "--repo", "alice/model", "--path", "new", "--allow-missing-path"]), api)
        self.assertEqual(self.events(), [{"event": "result", "data": []}])

    def test_token_and_ansi_are_removed(self):
        with patch.dict(os.environ, {"HF_TOKEN": "an unusual secret"}):
            bridge.emit("error", message="\x1b[31man unusual secret hf_abcdefghijk\x1b[0m")
        self.assertEqual(self.events()[0]["message"], "[redacted] [redacted]")

    def test_repo_info_preserves_actual_visibility_and_type(self):
        api = Mock()
        api.repo_info.return_value = SimpleNamespace(id="alice/data", private=True)
        bridge.execute(bridge.parser().parse_args(["info", "--repo", "alice/data", "--type", "dataset"]), api)
        api.repo_info.assert_called_once_with(repo_id="alice/data", repo_type="dataset")
        self.assertEqual(self.events()[0]["data"], {"id": "alice/data", "type": "dataset", "private": True, "url": "https://huggingface.co/datasets/alice/data"})

    def test_create_uses_explicit_visibility_and_never_overwrites(self):
        api = Mock()
        api.create_repo.return_value = "https://huggingface.co/alice/model"
        bridge.execute(bridge.parser().parse_args(["create", "--repo", "alice/model", "--private", "true"]), api)
        api.create_repo.assert_called_once_with(repo_id="alice/model", repo_type="model", private=True, exist_ok=False)


if __name__ == "__main__":
    unittest.main()
