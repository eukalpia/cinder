"""Compare normal terminal applications through the same real PTY driver.

One native 'n' key is outstanding at a time. Every completed frame must match
all expected cells. Latency includes the framework's frame pacing, input path,
native output, and parent observation; CPU time excludes this Python process.
"""
import argparse
import codecs
import fcntl
import json
import math
import os
from pathlib import Path
import platform
import pty
import re
import select
import signal
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import time
import traceback

import psutil
import pyte


class TerminalScreen(pyte.Screen):
    def __init__(self, width, height, master):
        self.master = master
        super().__init__(width, height)

    def write_process_input(self, text):
        os.write(self.master, text.encode())

    def scroll_up(self, count=1, *args, **kwargs):
        if args or kwargs.get('private'):
            return
        top, bottom = self.margins or (0, self.lines - 1)
        position = self.cursor.x, self.cursor.y
        self.cursor.y = bottom
        for _ in range(min(count or 1, bottom - top + 1)):
            self.index()
        self.cursor.x, self.cursor.y = position

    def scroll_down(self, count=1, *args, **kwargs):
        if args or kwargs.get('private'):
            return
        top, bottom = self.margins or (0, self.lines - 1)
        position = self.cursor.x, self.cursor.y
        self.cursor.y = top
        for _ in range(min(count or 1, bottom - top + 1)):
            self.reverse_index()
        self.cursor.x, self.cursor.y = position


class TerminalStream(pyte.Stream):
    # pyte 0.8.2 omits standard SU/SD. Dispatch these through its existing
    # margin-aware line operations, without moving the application cursor.
    # Private S and multi-parameter T have other xterm meanings, so the screen
    # handlers intentionally ignore them. See xterm's control sequence list:
    # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
    csi = dict(pyte.Stream.csi, S='scroll_up', T='scroll_down')
    events = pyte.Stream.events | {'scroll_up', 'scroll_down'}

    def _parser_fsm(self):
        parser = super()._parser_fsm()
        ready = next(parser)
        escaped = csi = secondary = False
        while True:
            character = yield ready
            if ready:
                escaped = character == '\x1b'
                csi = character == '\x9b'
                secondary = False
            elif escaped:
                csi = character == '['
                escaped = False
            elif csi and character == '>':
                secondary = True
            if csi and secondary and character in ('S', 'T'):
                # pyte discards '>' rather than passing its private prefix to
                # handlers. Mark this dispatch private before its final byte,
                # so xterm's title-mode reset (>T) cannot become a scroll.
                # Other commands and OSC strings keep pyte's original parsing.
                parser.send('?')
            ready = parser.send(character)


def quantile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def wait_for_session_host(process, read_output, timeout=5):
    # Darwin can block a session leader's exit until its queued PTY output is
    # consumed. Waiting without reading can therefore deadlock after the actual
    # adapter has exited successfully. This runs after all measured frames.
    deadline = time.monotonic() + timeout
    while process.poll() is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(process.args, timeout)
        read_output(min(.02, remaining))
    return process.returncode


def stop_session_host(process, read_output):
    errors = []
    if process is None or process.poll() is not None:
        return errors
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as error:
        errors.append(f'kill session group: {error!r}')
        # A denied group signal must not mask the original failure or prevent
        # attempts to stop the adapter and reap our own direct child.
        try:
            descendants = psutil.Process(process.pid).children(recursive=True)
        except psutil.NoSuchProcess:
            descendants = []
        except psutil.Error as error:
            errors.append(f'find session descendants: {error!r}')
            descendants = []
        for child in reversed(descendants):
            try:
                child.kill()
            except psutil.NoSuchProcess:
                pass
            except psutil.Error as error:
                errors.append(f'kill session descendant {child.pid}: {error!r}')
        try:
            process.kill()
        except ProcessLookupError:
            pass
        except OSError as error:
            errors.append(f'kill session host: {error!r}')
    try:
        wait_for_session_host(process, read_output)
    except Exception as error:
        errors.append(f'wait for session host: {error!r}')
    return errors


def io_snapshot(process):
    try:
        return process.io_counters(), None
    except (AttributeError, NotImplementedError, psutil.Error, OSError) as error:
        return None, f'{sys.platform}: {type(error).__name__}: {error}'


def io_delta(before, after, error):
    if before is None or after is None:
        return {'supported': False, 'reason': error}
    return {'supported': True, **{
        name: getattr(after, name) - getattr(before, name)
        for name in ('read_bytes', 'write_bytes', 'read_count', 'write_count')
    }}


def session_host(config_path, state_path, release_path):
    """Keep the controlling session alive while inspecting child cleanup.

    Darwin revokes a PTY when its session leader exits. A shell normally keeps
    that session alive after an application exits; this quiet host does likewise.
    All usage measurements target the application PID, excluding this host.
    """
    config = json.loads(Path(config_path).read_text())
    state_file = Path(state_path)
    started = time.perf_counter_ns()
    child = subprocess.Popen(config['command'])
    state = {'pid': child.pid, 'started_ns': started, 'exit_code': None}

    def publish():
        temporary = state_file.with_suffix('.tmp')
        temporary.write_text(json.dumps(state))
        temporary.replace(state_file)

    publish()
    state['exit_code'] = child.wait()
    publish()
    deadline = time.monotonic() + 30
    while not Path(release_path).exists() and time.monotonic() < deadline:
        time.sleep(.01)


def run(args):
    workload = json.loads(args.workload.read_text())
    width, height = workload['width'], workload['height']
    frames = [frame.split('\n') for frame in workload['frames']]
    if not frames or any(len(frame) != height or
                         any(len(row) != width for row in frame) for frame in frames):
        raise ValueError('Workload dimensions do not match its text states')
    if any(frame == frames[(index + 1) % len(frames)] for index, frame in enumerate(frames)):
        raise ValueError('Every update must change the visible screen')
    if (args.frames < 1 or args.warmup < 0 or args.settle_seconds < 0 or
            not math.isfinite(args.settle_seconds)):
        raise ValueError('frames must be positive; warmup and settle-seconds must be finite and nonnegative')
    command = list(args.command)
    if command and command[0] == '--':
        command.pop(0)
    if not command:
        raise ValueError('Provide the adapter command after --')
    command.append(str(args.workload.resolve()))
    environment = dict(os.environ)
    for key in ['TERM_PROGRAM', 'TERM_PROGRAM_VERSION', 'TMUX', 'STY',
                'SSH_TTY', 'SSH_CONNECTION', 'SSH_CLIENT', 'NO_COLOR',
                'FORCE_COLOR', 'VTE_VERSION', 'LC_TERMINAL']:
        environment.pop(key, None)
    environment.update(TERM='xterm-256color', COLORTERM='truecolor', CI='false',
                       NODE_ENV='production', CINDER_FORCE_INTERACTIVE='1',
                       COLUMNS=str(width), LINES=str(height))
    master, slave = pty.openpty()
    before_modes = termios.tcgetattr(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
    screen = TerminalScreen(width, height, master)
    stream = TerminalStream(screen)
    decoder = codecs.getincrementaldecoder('utf-8')('replace')
    raw = bytearray()
    pending_queries = bytearray()
    marker_tail = b''
    sync_ends = 0
    last_read_ns = 0
    frame_chunks = []

    def read_output(timeout):
        nonlocal sync_ends, marker_tail, last_read_ns
        if not select.select([master], [], [], timeout)[0]:
            return
        try:
            chunk = os.read(master, 1024 * 1024)
        except OSError:
            return
        last_read_ns = time.perf_counter_ns()
        raw.extend(chunk)
        if len(raw) > 128 * 1024 * 1024:
            raise AssertionError('Unbounded terminal output')
        stream.feed(decoder.decode(chunk))
        combined = marker_tail + chunk
        sync_ends += combined.count(b'\x1b[?2026l')
        marker_tail = combined[-7:]
        pending_queries.extend(chunk)
        responses = {
            b'\x1b[?2026$p': b'\x1b[?2026;2$y',
            b'\x1b[?2027$p': b'\x1b[?2027;0$y',
            b'\x1b[>c': b'\x1b[>0;400;0c',
            b'\x1b[>0c': b'\x1b[>0;400;0c',
            b'\x1b[18t': f'\x1b[8;{height};{width}t'.encode(),
            b'\x1b[16t': b'\x1b[6;16;8t',
        }
        for query, response in responses.items():
            while query in pending_queries:
                os.write(master, response)
                pending_queries[:] = pending_queries.replace(query, b'', 1)
        for match in list(re.finditer(rb'\x1b\](10|11);\?(?:\x07|\x1b\\)', pending_queries)):
            color = b'ffff/ffff/ffff' if match.group(1) == b'10' else b'0000/0000/0000'
            os.write(master, b'\x1b]' + match.group(1) + b';rgb:' + color + b'\x1b\\')
        pending_queries[:] = re.sub(rb'\x1b\](10|11);\?(?:\x07|\x1b\\)', b'', pending_queries)
        del pending_queries[:-128]

    def prepare_terminal():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    with tempfile.TemporaryDirectory(prefix='cinder_frame_bench_') as directory:
        errors_path = Path(directory) / 'stderr.log'
        config_path = Path(directory) / 'command.json'
        state_path = Path(directory) / 'state.json'
        release_path = Path(directory) / 'release'
        config_path.write_text(json.dumps({'command': command}))
        process = None
        succeeded = False
        try:
            with errors_path.open('wb') as errors:
                process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                                            '_session-host', str(config_path),
                                            str(state_path), str(release_path)],
                                           stdin=slave, stdout=slave,
                                           stderr=errors, cwd=directory,
                                           env=environment, preexec_fn=prepare_terminal)
            deadline = time.monotonic() + 20
            while not state_path.exists() and time.monotonic() < deadline:
                if process.poll() is not None:
                    raise AssertionError(f'Session host failed: {errors_path.read_text()}')
                read_output(.01)
            state = json.loads(state_path.read_text())
            started = state['started_ns']
            usage = psutil.Process(state['pid'])

            def child_exit_code():
                return json.loads(state_path.read_text())['exit_code']

            def wait_frame(expected, previous_sync, seconds):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if screen.display == expected and (
                            previous_sync is None or sync_ends > previous_sync):
                        # Timestamp data receipt, before decoding/verification.
                        return last_read_ns
                    if child_exit_code() is not None or process.poll() is not None:
                        raise AssertionError(f'Adapter exited {child_exit_code()}: {errors_path.read_text()}')
                    read_output(0.01)
                differences = [(i, wanted, got) for i, (wanted, got) in
                               enumerate(zip(expected, screen.display)) if wanted != got]
                raise AssertionError(f'Frame timeout; first differences: {differences[:3]}; '
                                     f'sync markers: {previous_sync}->{sync_ends}; '
                                     f'stderr: {errors_path.read_text()}')

            ready = wait_frame(frames[0], None, 20)
            startup_ms = (ready - started) / 1e6
            settle_deadline = time.monotonic() + args.settle_seconds
            while time.monotonic() < settle_deadline:
                if child_exit_code() is not None or process.poll() is not None:
                    raise AssertionError(f'Adapter exited while settling: {errors_path.read_text()}')
                read_output(min(.02, max(0, settle_deadline - time.monotonic())))
            if screen.display != frames[0]:
                raise AssertionError('Adapter changed the initial grid during settling')
            latencies = []
            rss_samples = []
            cpu_start = None
            measured_start = None
            measured_bytes = None
            io_start = None
            io_error = None
            for frame_index in range(1, args.warmup + args.frames + 1):
                if frame_index == args.warmup + 1:
                    io_start, io_error = io_snapshot(usage)
                    cpu_start = usage.cpu_times()
                    measured_start = time.perf_counter_ns()
                    measured_bytes = len(raw)
                previous_sync = sync_ends if sync_ends else None
                frame_start = len(raw)
                sent = time.perf_counter_ns()
                os.write(master, b'n')
                completed = wait_frame(frames[frame_index % len(frames)], previous_sync, 5)
                if frame_index > args.warmup:
                    latencies.append((completed - sent) / 1e6)
                    rss_samples.append(usage.memory_info().rss)
                    frame_chunks.append(len(raw) - frame_start)
            measured_end = time.perf_counter_ns()
            cpu_end = usage.cpu_times()
            io_end, io_end_error = io_snapshot(usage)
            cpu_seconds = (cpu_end.user - cpu_start.user) + (cpu_end.system - cpu_start.system)
            byte_count = len(raw) - measured_bytes
            args.result.parent.mkdir(parents=True, exist_ok=True)
            args.result.with_suffix('.ansi').write_bytes(raw)
            os.write(master, b'q')
            deadline = time.monotonic() + 5
            while child_exit_code() is None and time.monotonic() < deadline:
                read_output(0.02)
            if child_exit_code() is None:
                raise AssertionError('Adapter did not exit after q')
            if child_exit_code() != 0:
                raise AssertionError(f'Adapter exited {child_exit_code()}: {errors_path.read_text()}')
            after_modes = termios.tcgetattr(slave)
            expected_modes, actual_modes = list(before_modes), list(after_modes)
            # Darwin sets PENDIN on raw->canonical restoration even when the
            # exact saved termios is supplied. It is pending-input kernel state;
            # all other flags and control characters must match exactly.
            ignored_state = getattr(termios, 'PENDIN', 0) if sys.platform == 'darwin' else 0
            expected_modes[3] &= ~ignored_state
            actual_modes[3] &= ~ignored_state
            if actual_modes != expected_modes:
                raise AssertionError('Adapter did not restore terminal input modes')
            stderr_bytes = errors_path.read_bytes()
            # Ink's normal restore-cursor dependency writes this on process
            # exit even when stderr is redirected. Preserve and record it.
            if stderr_bytes.replace(b'\x1b[?25h', b''):
                raise AssertionError(f'Adapter wrote unexpected stderr: {stderr_bytes!r}')
            release_path.touch()
            host_exit_code = wait_for_session_host(process, read_output)
            if host_exit_code != 0:
                raise AssertionError(f'Session host exited {host_exit_code}: {errors_path.read_text()}')
            alt_enter = raw.rfind(b'\x1b[?1049h')
            alt_leave = raw.rfind(b'\x1b[?1049l')
            terminal_cleanup = {
                'alternate_screen_exit_observed': None if alt_enter < 0 else alt_leave > alt_enter,
                'cursor_show_observed': b'\x1b[?25h' in raw or b'\x1b[?25h' in stderr_bytes,
            }
            result = {
                'adapter': args.label, 'command': command,
                'workload': workload['name'], 'width': width, 'height': height,
                'configured_fps': workload['fps'], 'warmup_frames': args.warmup,
                'settle_seconds': args.settle_seconds,
                'measured_frames': args.frames, 'startup_ms': startup_ms,
                'arrival_pattern': 'one native key after preceding verified frame',
                'boundary': 'PTY input write to observed complete visible grid and available sync end',
                'wall_seconds': (measured_end - measured_start) / 1e9,
                'cpu_seconds': cpu_seconds, 'cpu_ms_per_frame': cpu_seconds * 1000 / args.frames,
                'process_io': io_delta(io_start, io_end, io_error or io_end_error),
                'rss_median_bytes': statistics.median(rss_samples),
                'rss_max_observed_bytes': max(rss_samples),
                'rss_samples_bytes': rss_samples,
                'output_bytes': byte_count, 'output_bytes_per_frame': byte_count / args.frames,
                'latency_ms': {'p50': quantile(latencies, .50), 'p95': quantile(latencies, .95),
                               'p99': quantile(latencies, .99), 'samples': latencies},
                'frame_output_bytes': frame_chunks, 'screen_verified_frames': args.warmup + args.frames + 1,
                'synchronized_output_ends': sync_ends,
                'stderr_cleanup_hex': stderr_bytes.hex(),
                'terminal_modes_restored': True,
                'terminal_cleanup': terminal_cleanup,
                'terminal_lflag_before': before_modes[3],
                'terminal_lflag_after': after_modes[3],
                'ignored_terminal_kernel_state_mask': ignored_state,
                'host': {'system': platform.platform(), 'machine': platform.machine(),
                         'python': platform.python_version()},
            }
            args.result.write_text(json.dumps(result, indent=2) + '\n')
            succeeded = True
            print(json.dumps({key: result[key] for key in ['adapter', 'workload',
                              'cpu_ms_per_frame', 'rss_median_bytes', 'output_bytes_per_frame']}))
        finally:
            original_error = sys.exc_info()
            diagnostics = {}
            if not succeeded:
                diagnostics = {
                    'error': f'{type(original_error[1]).__name__}: {original_error[1]}',
                    'traceback': ''.join(traceback.format_exception(*original_error)),
                    'command': command,
                    'session_host_pid': None if process is None else process.pid,
                }
                try:
                    diagnostics['adapter_state'] = json.loads(state_path.read_text())
                    if process is not None:
                        diagnostics['session_host_status'] = psutil.Process(process.pid).status()
                except (OSError, ValueError, psutil.Error) as error:
                    diagnostics['state_error'] = repr(error)
            cleanup_errors = stop_session_host(process, read_output)
            for descriptor in (master, slave):
                try:
                    os.close(descriptor)
                except OSError as error:
                    cleanup_errors.append(f'close PTY descriptor: {error!r}')
            if not succeeded:
                diagnostics['cleanup_errors'] = cleanup_errors
                diagnostics['session_host_exit_code'] = None if process is None else process.poll()
                try:
                    args.result.parent.mkdir(parents=True, exist_ok=True)
                    args.result.with_suffix('.failure.ansi').write_bytes(raw)
                    args.result.with_suffix('.failure.stderr').write_bytes(errors_path.read_bytes())
                    args.result.with_suffix('.failure.json').write_text(json.dumps(diagnostics, indent=2) + '\n')
                except OSError as error:
                    print(f'Could not preserve failure diagnostics: {error!r}', file=sys.stderr)
            if cleanup_errors:
                print('Session cleanup diagnostics: ' + '; '.join(cleanup_errors), file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '_session-host':
        session_host(*sys.argv[2:])
        sys.exit(0)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workload', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--frames', type=int, default=180)
    parser.add_argument('--warmup', type=int, default=30)
    parser.add_argument('--settle-seconds', type=float, default=6,
                        help='drain capability negotiation after the first frame, before warmup')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    run(parser.parse_args())
