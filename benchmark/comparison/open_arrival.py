"""Fixed-arrival input scheduling and coalesced state-visibility accounting.

The sender is a separate process. Its telemetry pipe is nonblocking, so pyte
decoding cannot hold up keyboard writes. Actual scheduling delays are retained.
"""
import json
import math
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import time


def clock_ns():
    """One system-wide monotonic epoch, including Python 3.9 on macOS.

    Older macOS Python gives perf_counter/monotonic per-process origins, which
    cannot timestamp an independently scheduled input process against the reader.
    """
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def percentiles(values):
    ordered = sorted(values)
    return {**{name: ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]
               for name, fraction in [('p50', .50), ('p95', .95), ('p99', .99)]},
            'samples': values}


class StateVisibility:
    def __init__(self, frames, *, start_step, event_count, deadline_ms):
        self.frames = frames
        self.start_step = self.last_step = start_step
        self.final_step = start_step + event_count
        self.deadline_ns = round(deadline_ms * 1000000)
        self.sends = []
        self.observations = []
        self.visible = {}
        self.duplicate_complete_states = 0

    def record_send(self, event):
        expected = self.start_step + len(self.sends) + 1
        if event['step'] != expected or expected > self.final_step:
            raise AssertionError(f'Input trace is not consecutive at step {expected}')
        if not event['nominal_ns'] <= event['sent_ns'] <= event['write_completed_ns']:
            raise AssertionError(f'Invalid send timestamps at step {expected}')
        self.sends.append(event)

    def observe(self, display, received_ns, verified_ns, output_offset, *, strict):
        match = re.match(r'Workspace step=(\d+) ', display[0])
        step = int(match.group(1)) if match else None
        if step is None or not self.start_step <= step <= self.final_step:
            if strict:
                raise AssertionError(f'Completed screen has invalid workspace step: {step}')
            return False
        if display != self.frames[step]:
            if strict:
                differences = [index for index, (actual, expected) in
                               enumerate(zip(display, self.frames[step])) if actual != expected]
                raise AssertionError(f'Completed step {step} differs from oracle; rows {differences[:5]}')
            return False
        if step < self.last_step:
            raise AssertionError(f'Complete workspace state regressed: {self.last_step} -> {step}')
        if step == self.last_step:
            self.duplicate_complete_states += 1
            return False
        frame = {'step': step, 'completing_chunk_received_ns': received_ns,
                 'screen_verified_ns': clock_ns() if verified_ns is None else verified_ns,
                 'terminal_output_end_offset': output_offset,
                 'completion': 'synchronized-output close' if strict else 'exact screen after PTY read'}
        for index in range(self.last_step + 1, step + 1):
            self.visible[index] = frame
        self.last_step = step
        self.observations.append(frame)
        return True

    def _visibility(self, step):
        return self.visible.get(step)

    def check_deadlines(self, now_ns):
        for event in self.sends:
            frame = self._visibility(event['step'])
            end = now_ns if frame is None else frame['completing_chunk_received_ns']
            if end < event['sent_ns']:
                raise AssertionError(f'State for step {event["step"]} was visible before input was sent')
            if end - event['sent_ns'] > self.deadline_ns:
                raise TimeoutError(f'State-visibility deadline exceeded for step {event["step"]} '
                                   f'from actual send; last complete step {self.last_step}')

    def finish(self):
        if self.last_step != self.final_step:
            raise AssertionError(f'Missing final step {self.final_step}; observed {self.last_step}')
        if len(self.sends) != self.final_step - self.start_step:
            raise AssertionError('Missing input delivery trace')
        self.check_deadlines(self.observations[-1]['completing_chunk_received_ns'])
        events = []
        for event in self.sends:
            frame = self._visibility(event['step'])
            received = frame['completing_chunk_received_ns']
            events.append({**event, 'visible_at_step': frame['step'],
                           'visible_received_ns': received,
                           'visibility_latency_ms': (received - event['sent_ns']) / 1e6,
                           'nominal_visibility_latency_ms': (received - event['nominal_ns']) / 1e6,
                           'send_lateness_ms': (event['sent_ns'] - event['nominal_ns']) / 1e6,
                           'input_write_duration_ms': (event['write_completed_ns'] - event['sent_ns']) / 1e6})
        return {
            'events': events, 'presented_steps': [frame['step'] for frame in self.observations],
            'observed_complete_states': len(self.observations),
            'duplicate_complete_states': self.duplicate_complete_states,
            'unobserved_intermediate_states': len(events) - len(self.observations),
            'all_inputs_delivered': True, 'final_step_verified': self.final_step,
            'deadline_ms': self.deadline_ns / 1e6,
            'nominal_deadline_misses': sum(event['nominal_visibility_latency_ms'] > self.deadline_ns / 1e6 for event in events),
            'actual_send_deadline_misses': 0,
            'state_visibility_latency_ms': percentiles([event['visibility_latency_ms'] for event in events]),
            'nominal_state_visibility_latency_ms': percentiles([event['nominal_visibility_latency_ms'] for event in events]),
            'send_lateness_ms': percentiles([event['send_lateness_ms'] for event in events]),
        }


class FixedArrivalSender:
    def __init__(self, master):
        self.process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                                         '_sender', str(master)], pass_fds=(master,),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, bufsize=0)
        self.pending = bytearray()
        self.done = False
        self.eof = False
        if not select.select([self.process.stdout], [], [], 5)[0] or self.process.stdout.readline() != b'ready\n':
            self.close()
            raise RuntimeError('Fixed-arrival sender did not become ready')
        os.set_blocking(self.process.stdout.fileno(), False)

    def start(self, keys, *, first_step, start_ns, interval_ms, deadline_ms):
        config = {'keys': keys, 'first_step': first_step, 'start_ns': start_ns,
                  'interval_ns': round(interval_ms * 1e6), 'deadline_ns': round(deadline_ms * 1e6)}
        self.process.stdin.write((json.dumps(config) + '\n').encode())
        self.process.stdin.close()

    def collect(self, ledger):
        while True:
            try:
                chunk = os.read(self.process.stdout.fileno(), 65536)
            except BlockingIOError:
                break
            if not chunk:
                self.eof = True
                break
            self.pending.extend(chunk)
        while b'\n' in self.pending:
            line, _, rest = self.pending.partition(b'\n')
            self.pending[:] = rest
            event = json.loads(line)
            if event.get('done'):
                self.done = True
            else:
                ledger.record_send(event)
        status = self.process.poll()
        if status is not None and (status != 0 or (self.eof and not self.done)):
            raise RuntimeError(f'Fixed-arrival sender failed ({status}): {self.process.stderr.read().decode()}')

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
            if stream is not None and not stream.closed:
                stream.close()


def sender_main(master):
    os.set_blocking(master, False)
    os.write(1, b'ready\n')
    config = json.loads(sys.stdin.readline())
    os.set_blocking(1, False)
    pending = bytearray()

    def emit(event):
        pending.extend((json.dumps(event, separators=(',', ':')) + '\n').encode())
        flush()

    def flush():
        if pending:
            try:
                count = os.write(1, pending)
                del pending[:count]
            except BlockingIOError:
                pass

    for index, key in enumerate(config['keys']):
        nominal = config['start_ns'] + index * config['interval_ns']
        while True:
            remaining = nominal - clock_ns()
            if remaining <= 0:
                break
            time.sleep(remaining / 1e9)
        while True:
            sent = clock_ns()
            if sent - nominal > config['deadline_ns']:
                raise TimeoutError(f'Could not deliver scheduled input {index + 1} before nominal send deadline')
            try:
                if os.write(master, key.encode('ascii')) != 1:
                    raise AssertionError('Input key must be one byte')
                break
            except BlockingIOError:
                select.select([], [master], [], .001)
        completed = clock_ns()
        emit({'step': config['first_step'] + index, 'key': key, 'nominal_ns': nominal,
              'sent_ns': sent, 'write_completed_ns': completed})
    emit({'done': True})
    while pending:
        select.select([], [1], [], .05)
        flush()


if __name__ == '__main__' and len(sys.argv) == 3 and sys.argv[1] == '_sender':
    sender_main(int(sys.argv[2]))
