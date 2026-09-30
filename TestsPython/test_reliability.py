"""Controlled local lifecycle checks; no remote account or network required."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("reliability", Path(__file__).parents[1] / "Scripts/reliability.py")
reliability = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reliability)
HAS_HF = importlib.util.find_spec("huggingface_hub") is not None


class ReliabilityTests(unittest.TestCase):
    def test_production_compare_caps_and_early_exit(self):
        result = reliability.compare_checks(reliability.load_bridge())
        self.assertEqual(result["listing_cap"], 100000)
        self.assertEqual(result["early_exit_entries"], 2000)

    @unittest.skipUnless(HAS_HF, "Use the managed HF runtime for SDK failure checks")
    def test_injected_sdk_failures_never_emit_success(self):
        result = reliability.failure_checks(reliability.load_bridge())
        self.assertEqual(len(result["injected_errors"]), 4)
        self.assertEqual(result["real_network_requests"], 0)

    @unittest.skipUnless(HAS_HF, "Use the managed HF runtime for subprocess lifecycle checks")
    def test_repeated_stop_reaps_children_and_restart_reads_checkpoint(self):
        with tempfile.TemporaryDirectory(prefix="face-hugger-cycle-test-") as temporary:
            root = Path(temporary)
            source = root / "source"; source.mkdir()
            (source / "sample.txt").write_text("fixture")
            result = reliability.lifecycle_checks(source, root / "checkpoint", 3)
            self.assertEqual(result["fixture_checkpoint"], 4)
            self.assertTrue(result["final_success"])
        self.assertFalse(root.exists())


if __name__ == "__main__":
    unittest.main()
