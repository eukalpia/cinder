"""A fixed-arrival report requires complete matching state-visibility evidence."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from summarize import summarize


class ArrivalSummaryTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.matrix = dict(arrival_interval_ms=4, event_deadline_ms=5000, frames=4,
                           warmup=2, fps=60, width=120, height=40, settle_seconds=6,
                           rounds=1, workloads=['workspace-100'])
        self.result = dict(measured_inputs=4, warmup_frames=2, configured_fps=60,
                           width=120, height=40, settle_seconds=6, arrival_interval_ms=4,
                           adapter='fixture', workload='workspace-100',
                           command=['app', 'workload.json'], terminal_modes_restored=True,
                           screen_verified_frames=5, cpu_ms_per_input=1,
                           rss_median_bytes=1048576, output_bytes_per_input=30,
                           state_visibility=dict(all_inputs_delivered=True, final_step_verified=6,
                               deadline_ms=5000, actual_send_deadline_misses=0,
                               events=[{}] * 4, observed_complete_states=2,
                               unobserved_intermediate_states=2,
                               state_visibility_latency_ms=dict(p50=2, p95=4, p99=4),
                               nominal_state_visibility_latency_ms=dict(p50=3, p95=5, p99=5),
                               send_lateness_ms=dict(p99=1)))
        (self.path / 'matrix.json').write_text(json.dumps(self.matrix))
        (self.path / 'configuration.json').write_text(json.dumps({'adapters': {'fixture': ['app']}}))

    def report(self):
        (self.path / 'fixture-workspace-100-1.json').write_text(json.dumps(self.result))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            summarize(self.path)
        return output.getvalue()

    def test_completed_coalesced_trial_reports_inputs_and_visibility(self):
        report = self.report()
        self.assertIn('CPU ms/input', report)
        self.assertIn('4 ms', report)
        self.assertIn('50.0', report)
        self.assertNotIn('CPU ms/frame', report)

    def test_missing_final_step_rejects_report(self):
        self.result['state_visibility']['final_step_verified'] = 5
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            self.report()

    def test_missing_delivery_trace_rejects_report(self):
        self.result['state_visibility']['events'].pop()
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            self.report()

    def test_mismatched_arrival_rate_rejects_report(self):
        self.result['arrival_interval_ms'] = 20
        with self.assertRaisesRegex(ValueError, 'mismatched'):
            self.report()


if __name__ == '__main__':
    unittest.main()
