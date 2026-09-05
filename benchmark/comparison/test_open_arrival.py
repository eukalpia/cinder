"""Exact state visibility, coalescing, and deadline rules for fixed arrivals."""
import os
import select
import subprocess
import sys
import time
import unittest

from data_workload import Workspace, workload
from open_arrival import FixedArrivalSender, StateVisibility, clock_ns


class StateVisibilityTest(unittest.TestCase):
    def setUp(self):
        model = Workspace(workload(100, 12, 60, 100))
        self.frames = [model.lines()]
        for key in 'jpxk':
            model.apply(key)
            self.frames.append(model.lines())

    def ledger(self, deadline_ms=50):
        ledger = StateVisibility(self.frames, start_step=0, event_count=4,
                                 deadline_ms=deadline_ms)
        for step in range(1, 5):
            ledger.record_send({'step': step, 'key': 'jpxk'[step - 1],
                                'nominal_ns': step * 1000000,
                                'sent_ns': step * 1000000 + 100000,
                                'write_completed_ns': step * 1000000 + 110000})
        return ledger

    def test_coalesced_states_cover_every_input_at_first_later_screen(self):
        ledger = self.ledger()
        ledger.observe(self.frames[2], 10000000, 10100000, 100, strict=True)
        ledger.observe(self.frames[4], 20000000, 20100000, 200, strict=True)
        result = ledger.finish()
        self.assertEqual(result['presented_steps'], [2, 4])
        self.assertEqual(result['unobserved_intermediate_states'], 2)
        self.assertEqual([event['visible_at_step'] for event in result['events']], [2, 2, 4, 4])
        self.assertEqual(result['events'][0]['visibility_latency_ms'], 8.9)
        self.assertEqual(result['events'][0]['nominal_visibility_latency_ms'], 9.0)

    def test_regressing_complete_state_is_rejected(self):
        ledger = self.ledger()
        ledger.observe(self.frames[2], 10000000, 10100000, 100, strict=True)
        with self.assertRaisesRegex(AssertionError, 'regressed'):
            ledger.observe(self.frames[1], 11000000, 11100000, 120, strict=True)

    def test_complete_step_must_be_within_scheduled_range(self):
        ledger = self.ledger()
        wrong = list(self.frames[4])
        wrong[0] = wrong[0].replace('step=000004', 'step=000005')
        with self.assertRaisesRegex(AssertionError, 'invalid workspace step'):
            ledger.observe(wrong, 10000000, 10100000, 100, strict=True)

    def test_sync_close_requires_exact_oracle_and_partial_read_can_wait(self):
        ledger = self.ledger()
        wrong = list(self.frames[2])
        wrong[3] = '?' * 100
        self.assertFalse(ledger.observe(wrong, 10000000, 10100000, 100, strict=False))
        with self.assertRaisesRegex(AssertionError, 'oracle'):
            ledger.observe(wrong, 10000000, 10100000, 100, strict=True)

    def test_missing_final_state_cannot_pass(self):
        ledger = self.ledger()
        ledger.observe(self.frames[3], 10000000, 10100000, 100, strict=True)
        with self.assertRaisesRegex(AssertionError, 'final step'):
            ledger.finish()


    def test_unseen_input_deadline_is_from_actual_send(self):
        ledger = self.ledger(deadline_ms=5)
        ledger.check_deadlines(6000000)
        with self.assertRaisesRegex(TimeoutError, 'step 1'):
            ledger.check_deadlines(6200000)

    def test_late_visibility_is_rejected_even_if_receipt_precedes_trace(self):
        ledger = StateVisibility(self.frames, start_step=0, event_count=4, deadline_ms=5)
        ledger.observe(self.frames[4], 20000000, 20100000, 100, strict=True)
        ledger.record_send({'step': 1, 'key': 'j', 'nominal_ns': 1000000,
                            'sent_ns': 1100000, 'write_completed_ns': 1110000})
        with self.assertRaisesRegex(TimeoutError, 'step 1'):
            ledger.check_deadlines(21000000)

    def test_representing_an_unsent_event_is_rejected(self):
        ledger = self.ledger()
        ledger.observe(self.frames[4], 2000000, 2100000, 100, strict=True)
        with self.assertRaisesRegex(AssertionError, 'before.*sent'):
            ledger.finish()


class FixedArrivalSenderTest(unittest.TestCase):
    def test_clock_has_the_same_origin_in_separate_processes(self):
        before = clock_ns()
        child = int(subprocess.check_output([
            sys.executable, '-c', 'from open_arrival import clock_ns; print(clock_ns())'],
            cwd=os.path.dirname(__file__)))
        after = clock_ns()
        self.assertLessEqual(before, child)
        self.assertLessEqual(child, after)

    def test_nominal_schedule_and_actual_delivery_trace_are_consecutive(self):
        read_fd, write_fd = os.pipe()
        sender = FixedArrivalSender(write_fd)
        model = Workspace(workload(100, 12, 60, 100))
        ledger = StateVisibility([model.lines()], start_step=24, event_count=4, deadline_ms=2000)
        try:
            start = clock_ns()
            sender.start(list('jpxk'), first_step=25, start_ns=start,
                         interval_ms=4, deadline_ms=2000)
            received = bytearray()
            deadline = time.monotonic() + 2
            while (not sender.done or len(received) < 4) and time.monotonic() < deadline:
                if select.select([read_fd], [], [], .005)[0]:
                    received.extend(os.read(read_fd, 4))
                sender.collect(ledger)
            self.assertTrue(sender.done)
            self.assertEqual(received, b'jpxk')
            self.assertEqual([event['step'] for event in ledger.sends], [25, 26, 27, 28])
            self.assertEqual([event['nominal_ns'] - start for event in ledger.sends],
                             [0, 4000000, 8000000, 12000000])
        finally:
            sender.close()
            os.close(read_fd)
            os.close(write_fd)

    def test_full_telemetry_pipe_cannot_delay_input_delivery(self):
        read_fd, write_fd = os.pipe()
        sender = FixedArrivalSender(write_fd)
        try:
            count = 2000
            sender.start(['j'] * count, first_step=1, start_ns=clock_ns(),
                         interval_ms=0, deadline_ms=2000)
            received = bytearray()
            deadline = time.monotonic() + 2
            # Do not collect telemetry: its pipe fills long before 2000 records.
            while len(received) < count and time.monotonic() < deadline:
                if select.select([read_fd], [], [], .05)[0]:
                    received.extend(os.read(read_fd, count))
            self.assertEqual(received, b'j' * count)
        finally:
            sender.close()
            os.close(read_fd)
            os.close(write_fd)



if __name__ == '__main__':
    unittest.main()
