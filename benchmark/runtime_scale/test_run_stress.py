import json
from pathlib import Path
import tempfile
import unittest

from run_stress import Samples


def sample(**changes):
    return {"rss_bytes": 1000, "elapsed_ms": 31000, "disposed": False,
            "live_records": 32, "history_limit": 32, "active_searches": 1,
            "pending_searches": 1, "query_code_units": 256, "task_history": 8,
            "max_rows_per_frame": 46, "framework_errors": 0, **changes}


class SamplesTest(unittest.TestCase):
    def test_partial_writes_are_read_once_and_aggregated_without_retaining_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            reader = Samples(path)
            self.addCleanup(reader.close)
            reader.poll()
            payload = json.dumps(sample()).encode() + b"\n"
            path.write_bytes(payload[:20])
            reader.poll()
            self.assertEqual(reader.count, 0)
            with path.open("ab") as output:
                output.write(payload[20:])
            reader.poll()
            self.assertEqual(reader.count, 1)
            with path.open("ab") as output:
                output.write(json.dumps(sample(rss_bytes=1500)).encode() + b"\n")
            reader.poll()
            reader.poll()
            self.assertEqual(reader.count, 2)
            self.assertEqual(reader.rss_min, 1000)
            self.assertEqual(reader.rss_max, 1500)
            self.assertEqual(reader.warm_rss_first, 1000)
            self.assertEqual(reader.warm_rss_last, 1500)
            self.assertEqual(reader.errors, [])

    def test_runtime_cap_violations_fail_even_when_final_state_is_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            path.write_text(json.dumps(sample(live_records=33, active_searches=2,
                                             query_code_units=257, task_history=9,
                                             max_rows_per_frame=100000)) + "\n"
                            + json.dumps(sample()) + "\n")
            reader = Samples(path)
            self.addCleanup(reader.close)
            reader.poll()
            self.assertEqual(reader.errors, ["history cap exceeded", "search concurrency cap exceeded",
                                            "query cap exceeded", "task history cap exceeded",
                                            "viewport row-work cap exceeded"])

    def test_oversized_metrics_line_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            path.write_text(json.dumps(sample(query="x" * 70000)) + "\n")
            reader = Samples(path)
            self.addCleanup(reader.close)
            with self.assertRaisesRegex(RuntimeError, "64 KiB"):
                reader.poll()


if __name__ == "__main__":
    unittest.main()
