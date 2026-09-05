"""Untimed regressions for terminal parsing and the driver's POSIX lifecycle."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

if os.name == 'posix':
    import fcntl
    import pty
    import termios

    module_spec = importlib.util.spec_from_file_location(
        'pty_driver', Path(__file__).with_name('run_pty.py'))
    driver = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(driver)


FIXTURE_SETUP = r'''
import json, os, sys, termios, tty
original_modes = termios.tcgetattr(0)
tty.setraw(0)
with open(sys.argv[1]) as source:
    frames = json.load(source)['frames']
def show(frame):
    os.write(1, ('\x1b[2J\x1b[H' + frame.replace('\n', '\r\n')).encode())
'''


@unittest.skipUnless(os.name == 'posix', 'The driver requires a POSIX PTY')
class TerminalScrollTest(unittest.TestCase):
    rows = ['A111', 'B222', 'C333', 'D444', 'E555']

    def terminal(self):
        screen = driver.TerminalScreen(4, 5, -1)
        stream = driver.TerminalStream(screen)
        for index, row in enumerate(self.rows):
            stream.feed(f'\x1b[{index + 1};1H{row}')
        return screen, stream

    def test_default_and_zero_count_scroll_one_row(self):
        for command in ('S', '0S', '1S', 'T', '0T', '1T'):
            with self.subTest(command=command):
                screen, stream = self.terminal()
                stream.feed('\x1b[' + command)
                expected = (self.rows[1:] + ['    '] if command.endswith('S')
                            else ['    '] + self.rows[:-1])
                self.assertEqual(screen.display, expected)

    def test_explicit_count_and_split_sequence(self):
        for command, expected in (
                ('S', self.rows[2:] + ['    '] * 2),
                ('T', ['    '] * 2 + self.rows[:-2])):
            with self.subTest(command=command):
                screen, stream = self.terminal()
                for fragment in ('\x1b', '[', '2', command):
                    stream.feed(fragment)
                self.assertEqual(screen.display, expected)

    def test_counts_clamp_to_scrolling_region_height(self):
        for command in ('S', 'T'):
            for count in (3, 4, 999999999):
                with self.subTest(command=command, count=count):
                    screen, stream = self.terminal()
                    stream.feed(f'\x1b[2;4r\x1b[{count}{command}')
                    self.assertEqual(screen.display, ['A111', '    ', '    ', '    ', 'E555'])

    def test_scroll_preserves_margins_and_cursor_inside_or_outside_region(self):
        for command, middle in (('S', ['C333', 'D444', '    ']),
                                ('T', ['    ', 'B222', 'C333'])):
            for cursor_row in (1, 3, 5):
                with self.subTest(command=command, cursor_row=cursor_row):
                    screen, stream = self.terminal()
                    stream.feed(f'\x1b[2;4r\x1b[{cursor_row};3H\x1b[31m\x1b[?25l')
                    cursor = (screen.cursor.x, screen.cursor.y,
                              screen.cursor.attrs, screen.cursor.hidden)
                    margins = screen.margins
                    stream.feed('\x1b[' + command)
                    self.assertEqual(screen.display, ['A111'] + middle + ['E555'])
                    self.assertEqual(screen.margins, margins)
                    self.assertEqual((screen.cursor.x, screen.cursor.y,
                                      screen.cursor.attrs, screen.cursor.hidden), cursor)

    def test_scroll_preserves_pending_wrap_cursor_column(self):
        for command in ('S', 'T'):
            with self.subTest(command=command):
                screen, stream = self.terminal()
                # Drawing the final column leaves x == columns until the next
                # printable character wraps; cursor_position would lose this.
                self.assertEqual(screen.cursor.x, screen.columns)
                position = (screen.cursor.x, screen.cursor.y)
                stream.feed('\x1b[' + command)
                self.assertEqual((screen.cursor.x, screen.cursor.y), position)

    def test_scrolled_cells_keep_their_attributes(self):
        screen, stream = self.terminal()
        stream.feed('\x1b[2;1H\x1b[31;44mB222\x1b[0m')
        original = screen.buffer[1][0]
        stream.feed('\x1b[S')
        self.assertEqual(screen.buffer[0][0], original)

    def test_private_graphics_and_multi_parameter_mouse_commands_do_not_scroll(self):
        screen, stream = self.terminal()
        for command in ('?1;1;0S', '?1S', '1;2;3;4;5T', '1;2S'):
            with self.subTest(command=command):
                stream.feed('\x1b[' + command)
                self.assertEqual(screen.display, self.rows)

    def test_secondary_title_controls_do_not_scroll_across_chunk_boundaries(self):
        for prefix in ('\x1b[', '\x9b'):
            for command in ('>T', '>0T', '>1T', '>1;2T', '>1S'):
                with self.subTest(prefix=prefix, command=command):
                    screen, stream = self.terminal()
                    for character in prefix + command:
                        stream.feed(character)
                    self.assertEqual(screen.display, self.rows)
                    stream.feed('\x1b[S')
                    self.assertEqual(screen.display, self.rows[1:] + ['    '])

    def test_secondary_prefix_in_osc_title_remains_title_text(self):
        screen, stream = self.terminal()
        title = 'a title with \x1b[>1T inside'
        stream.feed('\x1b]2;' + title + '\x07')
        self.assertEqual(screen.title, title)
        self.assertEqual(screen.display, self.rows)

    def test_sync_boundary_tracks_open_frame_after_a_closed_frame(self):
        boundary = driver.SyncBoundary()
        boundary.feed(b'\x1b[?2026hfirst\x1b[?2026l\x1b[?2026hsecond')
        self.assertEqual(boundary.ends, 1)
        self.assertTrue(boundary.active)
        boundary.feed(b'\x1b[?20')
        boundary.feed(b'26l')
        self.assertEqual(boundary.ends, 2)
        self.assertFalse(boundary.active)


@unittest.skipUnless(os.name == 'posix', 'The driver requires a POSIX PTY')
class DriverLifecycleTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cinder_driver_test_')
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.workload = self.directory / 'workload.json'
        self.workload.write_text(json.dumps({
            'name': 'test', 'width': 2, 'height': 2, 'fps': 60,
            'frames': ['AB\nCD', 'AB\nCZ'],
        }))

    def fixture_args(self, body, settle_seconds=0):
        fixture = self.directory / 'adapter.py'
        fixture.write_text(FIXTURE_SETUP + body)
        return argparse.Namespace(
            workload=self.workload, result=self.directory / 'result.json',
            label='test-adapter', frames=1, warmup=0,
            settle_seconds=settle_seconds, command=[sys.executable, str(fixture)])

    def host_paths(self, command):
        config, state, release = [self.directory / name for name in
                                  ('command.json', 'state.json', 'release')]
        config.write_text(json.dumps({'command': command}))
        host_command = [sys.executable, driver.__file__, '_session-host',
                        str(config), str(state), str(release)]
        return host_command, state, release

    def wait_state(self, path, exited=False):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if path.exists():
                state = json.loads(path.read_text())
                if not exited or state['exit_code'] is not None:
                    return state
            time.sleep(.005)
        self.fail('Session host did not publish the expected child state')

    def test_session_host_startup_uses_shared_clock_for_legacy_runs(self):
        command, state, release = self.host_paths(['app'])
        release.touch()
        with mock.patch.object(driver.subprocess, 'Popen') as child:
            child.return_value.pid = 123
            child.return_value.wait.return_value = 0
            with mock.patch.object(driver.time, 'perf_counter_ns', return_value=999):
                with mock.patch.object(driver.time, 'clock_gettime_ns', return_value=123456789):
                    driver.session_host(command[-3], state, release)
        self.assertEqual(json.loads(state.read_text())['started_ns'], 123456789)

    def test_legacy_startup_interval_stays_inside_driver_run(self):
        args = self.fixture_args(
            'show(frames[0])\nassert os.read(0, 1) == b"n"\nshow(frames[1])\n'
            'assert os.read(0, 1) == b"q"\n'
            'termios.tcsetattr(0, termios.TCSANOW, original_modes)\n')
        before = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        with mock.patch('builtins.print'):
            driver.run(args)
        after = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        result = json.loads(args.result.read_text())
        self.assertGreaterEqual(result['startup_ms'], 0)
        self.assertLessEqual(result['startup_ms'], (after - before) / 1e6)
        self.assertEqual(result['startup_timestamp_clock'], 'clock_gettime_ns(CLOCK_MONOTONIC)')

    def test_denied_group_kill_preserves_adapter_failure(self):
        args = self.fixture_args('show(frames[0])\nos.read(0, 1)\nsys.exit(7)\n')
        hosts = []

        def denied(pid, _signal):
            hosts.append(driver.psutil.Process(pid))
            raise PermissionError(1, 'injected group signal denial')

        try:
            with mock.patch.object(driver.os, 'killpg', side_effect=denied):
                with self.assertRaisesRegex(AssertionError, 'Adapter exited 7'):
                    driver.run(args)
            failure = json.loads(args.result.with_suffix('.failure.json').read_text())
            self.assertIn('Adapter exited 7', failure['error'])
            self.assertTrue(any('PermissionError' in error
                                for error in failure['cleanup_errors']))
            self.assertTrue(args.result.with_suffix('.failure.ansi').exists())
            self.assertEqual(args.result.with_suffix('.failure.stderr').read_bytes(), b'')
        finally:
            for host in hosts:
                try:
                    host.kill()
                except driver.psutil.NoSuchProcess:
                    pass
                try:
                    os.waitpid(host.pid, 0)
                except ChildProcessError:
                    pass

    @unittest.skipUnless(sys.platform == 'darwin', 'Darwin waits for pending PTY output on exit')
    def test_released_host_drains_pending_terminal_output(self):
        command, state_path, release = self.host_paths(
            [sys.executable, '-c', 'import os; os.write(1, b"X" * 256)'])
        master, slave = pty.openpty()

        def prepare():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        process = subprocess.Popen(command, stdin=slave, stdout=slave,
                                   stderr=subprocess.PIPE, preexec_fn=prepare)
        drained = bytearray()

        def read_output(timeout):
            if select.select([master], [], [], timeout)[0]:
                try:
                    drained.extend(os.read(master, 65536))
                except OSError:
                    pass

        try:
            self.assertEqual(self.wait_state(state_path, exited=True)['exit_code'], 0)
            release.touch()
            try:
                exit_code = driver.wait_for_session_host(process, read_output, timeout=1)
            except subprocess.TimeoutExpired:
                self.fail('Released host remained blocked by unread terminal output')
            self.assertEqual(exit_code, 0)
            self.assertEqual(drained, b'X' * 256)
        finally:
            read_output(.01)
            if process.poll() is None:
                process.kill()
            os.close(master)
            os.close(slave)
            process.wait(timeout=5)
            process.stderr.close()

    def test_denied_group_kill_stops_adapter_as_well_as_host(self):
        command, state_path, _release = self.host_paths(
            [sys.executable, '-c', 'import signal; signal.pause()'])
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, start_new_session=True)
        child = None
        try:
            child = driver.psutil.Process(self.wait_state(state_path)['pid'])
            with mock.patch.object(driver.os, 'killpg',
                                   side_effect=PermissionError(1, 'injected denial')):
                driver.stop_session_host(process, time.sleep)
            deadline = time.monotonic() + 2
            while (child.is_running() and child.status() != driver.psutil.STATUS_ZOMBIE
                   and time.monotonic() < deadline):
                time.sleep(.005)
            self.assertTrue(not child.is_running() or child.status() == driver.psutil.STATUS_ZOMBIE,
                            'Direct-host fallback leaked the adapter child')
        finally:
            if child is not None:
                try:
                    child.kill()
                    child.wait(timeout=2)
                except driver.psutil.Error:
                    pass
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)

    def test_settle_rejects_spontaneous_grid_change(self):
        # Wait for a real capability reply so the driver observes frame zero
        # before the fixture changes it. No startup sleep or timing race.
        args = self.fixture_args(
            'show(frames[0])\nos.write(1, b"\\x1b[?2026$p")\n'
            'os.read(0, 1024)\nshow(frames[1])\nos.read(0, 1024)\n',
            settle_seconds=.05)
        with self.assertRaisesRegex(AssertionError, 'changed the initial grid during settling'):
            driver.run(args)
        diagnostics = json.loads(args.result.with_suffix('.failure.json').read_text())
        self.assertIn('during settling', diagnostics['error'])

    def test_driver_checks_scroll_only_updates_through_real_pty(self):
        self.workload.write_text(json.dumps({
            'name': 'scroll', 'width': 2, 'height': 2, 'fps': 60,
            'frames': ['AB\nCD', 'CD\nEF'],
        }))
        args = self.fixture_args(
            'show(frames[0])\n'
            'assert os.read(0, 1) == b"n"\n'
            'os.write(1, b"\\x1b[S\\x1b[2;1HEF")\n'
            'assert os.read(0, 1) == b"n"\n'
            'os.write(1, b"\\x1b[T\\x1b[1;1HAB")\n'
            'assert os.read(0, 1) == b"q"\n'
            'termios.tcsetattr(0, termios.TCSANOW, original_modes)\n')
        args.frames = 2
        with mock.patch('builtins.print'):
            driver.run(args)
        result = json.loads(args.result.read_text())
        self.assertEqual(result['screen_verified_frames'], 3)
        self.assertTrue(result['terminal_modes_restored'])

    def test_terminal_output_on_stderr_keeps_normal_child_descriptors(self):
        args = self.fixture_args(
            'def show(frame):\n'
            '    os.write(2, ("\\x1b[2J\\x1b[H" + frame.replace("\\n", "\\r\\n")).encode())\n'
            'show(frames[0])\n'
            'assert os.read(0, 1) == b"n"\n'
            'show(frames[1])\n'
            'assert os.read(0, 1) == b"q"\n'
            'termios.tcsetattr(0, termios.TCSANOW, original_modes)\n')
        args.terminal_output = 'stderr'
        with mock.patch('builtins.print'):
            driver.run(args)
        result = json.loads(args.result.read_text())
        self.assertEqual(result['terminal_output_descriptor'], 'stderr')

    def test_fixed_arrivals_allow_coalescing_and_require_final_state(self):
        from data_workload import workload
        spec = workload(100, 12, 60, 100)
        spec['actions'] = list('jpxk')
        self.workload.write_text(json.dumps(spec))
        args = self.fixture_args('')
        args.frames = 4
        args.arrival_interval_ms = 4
        args.event_deadline_ms = 1000
        Path(args.command[1]).write_text(
            'import json, os, sys, termios, tty\n'
            f'sys.path.insert(0, {str(Path(driver.__file__).parent)!r})\n'
            'from data_workload import Workspace\n'
            'original_modes = termios.tcgetattr(0)\n'
            'tty.setraw(0)\n'
            'model = Workspace(json.load(open(sys.argv[1])))\n'
            'def show():\n'
            '    value = "\\r\\n".join(model.lines())\n'
            '    os.write(1, ("\\x1b[?2026h\\x1b[2J\\x1b[H" + value + "\\x1b[?2026l").encode())\n'
            'show()\n'
            'for batch in range(2):\n'
            '    for item in range(2):\n'
            '        model.apply(os.read(0, 1).decode())\n'
            '    show()\n'
            'assert os.read(0, 1) == b"q"\n'
            'termios.tcsetattr(0, termios.TCSANOW, original_modes)\n')
        with mock.patch('builtins.print'):
            driver.run(args)
        result = json.loads(args.result.read_text())
        self.assertEqual(result['state_visibility']['presented_steps'], [2, 4])
        self.assertEqual(result['state_visibility']['unobserved_intermediate_states'], 2)
        self.assertTrue(result['state_visibility']['all_inputs_delivered'])
        self.assertTrue(result['terminal_modes_restored'])


if __name__ == '__main__':
    unittest.main()
