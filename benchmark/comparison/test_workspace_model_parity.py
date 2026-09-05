"""Untimed Dart application model parity against the independent Python oracle."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from data_workload import ACTIONS, Workspace, workload

DART = os.environ.get('CINDER_BENCHMARK_DART') or shutil.which('dart')


@unittest.skipUnless(DART, 'Install Dart or set CINDER_BENCHMARK_DART for model parity')
class DartWorkspaceParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = workload(count=50000)
        spec['actions'] = list(ACTIONS) * 2
        with tempfile.TemporaryDirectory(prefix='cinder_dart_model_parity_') as directory:
            path = Path(directory) / 'workspace.json'
            path.write_text(json.dumps(spec))
            result = subprocess.run(
                [DART, str(Path(__file__).with_name('workspace_model_probe.dart')), str(path)],
                check=True, text=True, capture_output=True)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        cls.metadata, cls.actual = rows[0], rows[1:]
        oracle = Workspace(spec)
        cls.expected = []
        for key in [None, *spec['actions']]:
            if key is not None:
                oracle.apply(key)
            cls.expected.append({'text': '\n'.join(oracle.lines()),
                                 'selected': sorted(oracle.selected),
                                 'record_count': len(oracle.records),
                                 'matches': [row['id'] for row in oracle.matches]})

    def test_rows_do_not_retain_mutable_json_maps(self):
        self.assertTrue(self.metadata['owns_decoded_rows'])

    def test_fifty_thousand_records_match_every_state_across_two_action_cycles(self):
        self.assertEqual(len(self.actual), 49)
        self.assertEqual(len(self.actual), len(self.expected))
        for step, (actual, expected) in enumerate(zip(self.actual, self.expected)):
            with self.subTest(step=step):
                self.assertEqual(actual, expected)


if __name__ == '__main__':
    unittest.main()
