"""Exercise a compiled Cinder application in a real POSIX pseudo-terminal.

Usage: python3 tool/terminal_smoke.py /path/to/cinder-demo
"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


def exercise(binary, disabled_flags):
    master, slave = pty.openpty()
    initial = termios.tcgetattr(slave)
    initial[3] &= ~disabled_flags
    termios.tcsetattr(slave, termios.TCSANOW, initial)
    before = termios.tcgetattr(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
    environment = dict(os.environ, TERM='xterm-256color',
                       CINDER_FORCE_INTERACTIVE='1')
    process = subprocess.Popen([binary], stdin=slave, stdout=slave, stderr=slave,
                               start_new_session=True, env=environment)
    output = bytearray()

    def receive_until(predicate, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate():
                return
            readable, _, _ = select.select([master], [], [], 0.05)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > 8 * 1024 * 1024:
                    raise AssertionError('Unexpected unbounded terminal output')
        if not predicate():
            raise AssertionError('Timed out waiting for terminal state')

    try:
        receive_until(lambda: b'\x1b[?1049h' in output and len(output) > 1000, 10)
        for rows, columns in [(15, 45), (40, 120)]:
            previous_length = len(output)
            fcntl.ioctl(slave, termios.TIOCSWINSZ,
                        struct.pack('HHHH', rows, columns, 0, 0))
            os.kill(process.pid, signal.SIGWINCH)
            receive_until(lambda: len(output) > previous_length, 5)
        os.write(master, b'\t\x1b[<0;10;5M\x1b[<0;10;5m')
        os.kill(process.pid, signal.SIGINT)
        receive_until(lambda: process.poll() is not None, 10)
        # Drain protocol restoration written just before process exit.
        while select.select([master], [], [], 0)[0]:
            output.extend(os.read(master, 65536))
        if process.returncode != 0:
            raise AssertionError(f'Application exited with {process.returncode}')
        if b'\x1b[?1049l' not in output:
            raise AssertionError('Alternate screen was not restored')
        if termios.tcgetattr(slave) != before:
            raise AssertionError(f'Terminal attributes were not restored: before={before!r}, after={termios.tcgetattr(slave)!r}')
        for error in [b'Unhandled exception', b'Layout Error', b'Paint Error']:
            if error in output:
                raise AssertionError(f'Application displayed {error!r}')
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        os.close(master)
        os.close(slave)


if __name__ == '__main__':
    binary = os.path.abspath(sys.argv[1])
    for disabled_flags in [0, termios.ECHO, termios.ECHO | termios.ICANON]:
        exercise(binary, disabled_flags)
    print('PTY startup, resize, input, SIGINT, and original terminal modes passed')
