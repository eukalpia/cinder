#!/usr/bin/env python3
"""Exercise the real terminal app; stream samples to disk, never retain a run.

Python 3 standard library only. Build the app first; this runner never compiles.
"""
from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import urllib.parse
import urllib.request


class Samples:
    """Incremental JSONL reader and constant-space aggregate."""

    def __init__(self, path):
        self.path = Path(path)
        self.file = None
        self.pending = b""
        self.latest = None
        self.count = 0
        self.rss_min = None
        self.rss_max = 0
        self.warm_rss_first = None
        self.warm_rss_last = None
        self.errors = []

    def poll(self):
        if self.file is None:
            if not self.path.exists():
                return
            self.file = self.path.open("rb")
        while True:
            chunk = self.file.read(65536)
            if not chunk:
                break
            self.pending += chunk
            lines = self.pending.split(b"\n")
            self.pending = lines.pop()
            if len(self.pending) > 65536:
                raise RuntimeError("metrics line exceeds 64 KiB")
            for line in lines:
                if len(line) > 65536:
                    raise RuntimeError("metrics line exceeds 64 KiB")
                sample = json.loads(line)
                self.latest = sample
                self.count += 1
                rss = sample["rss_bytes"]
                self.rss_min = rss if self.rss_min is None else min(self.rss_min, rss)
                self.rss_max = max(self.rss_max, rss)
                if sample["elapsed_ms"] >= 30000 and not sample["disposed"]:
                    if self.warm_rss_first is None:
                        self.warm_rss_first = rss
                    self.warm_rss_last = rss
                failures = []
                if sample["live_records"] > sample["history_limit"]:
                    failures.append("history cap exceeded")
                if sample["active_searches"] > 1 or sample["pending_searches"] > 1:
                    failures.append("search concurrency cap exceeded")
                if sample["query_code_units"] > 256:
                    failures.append("query cap exceeded")
                if sample["task_history"] > 8:
                    failures.append("task history cap exceeded")
                if sample.get("framework_errors", 0):
                    failures.append("framework error reported")
                # The scripted viewport never exceeds 48 rows. A limit of two
                # viewport builds permits transition frames while still catching
                # eager construction of 100,000 records.
                if sample["max_rows_per_frame"] > 112:
                    failures.append("viewport row-work cap exceeded")
                for failure in failures:
                    if failure not in self.errors:
                        self.errors.append(failure)

    def close(self):
        if self.file:
            self.file.close()


def rpc(base, method, **params):
    url = base + method + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=10) as response:
        payload = response.read(16 * 1024 * 1024 + 1)
    if len(payload) > 16 * 1024 * 1024:
        raise RuntimeError("VM service response exceeded diagnostic limit")
    result = json.loads(payload)
    if "error" in result:
        raise RuntimeError(str(result["error"]))
    return result["result"]


def heap_sample(uri):
    """JIT-only intrusive diagnostic: force GC, then report heap/external use."""
    vm = rpc(uri, "getVM")
    isolates = [i for i in vm["isolates"] if not i.get("isSystemIsolate", False)]
    main = next((i for i in isolates if i["name"] == "main"), isolates[0])
    profile = rpc(uri, "getAllocationProfile", isolateId=main["id"], gc="true")
    memory = rpc(uri, "getMemoryUsage", isolateId=main["id"])
    classes = [{"class": member["class"]["name"],
                "instances": member.get("instancesCurrent", 0),
                "bytes": member.get("bytesCurrent", 0)}
               for member in profile["members"] if member.get("bytesCurrent", 0)]
    classes.sort(key=lambda item: item["bytes"], reverse=True)
    groups = {"direct_app_objects": 0, "direct_buffer_objects": 0,
              "typed_data_storage": 0, "other_managed_objects": 0}
    for item in classes:
        name = item["class"]
        if name.startswith(("Scale", "_Scale")):
            group = "direct_app_objects"
        elif "Buffer" in name or name in ("Cell", "CellStyle", "TerminalCanvas", "DisplayList"):
            group = "direct_buffer_objects"
        elif name.startswith(("_Uint", "_Int", "_Float")) and "List" in name:
            group = "typed_data_storage"
        else:
            group = "other_managed_objects"
        groups[group] += item["bytes"]
    return {"event": "heap", "runtime": "jit", "forced_gc": True,
            "isolate": main["name"], "after_gc": profile["memoryUsage"],
            "memory_usage": memory, "top_classes": classes[:20],
            "class_shallow_bytes": groups,
            "attribution": "Class-name inventory; shared backing lists and native VM/code memory are not ownership-attributed."}


def run_session(args, run):
    destination = Path(args.output).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    metrics_path = destination / f"run-{run:03d}.jsonl"
    # Refuse to overwrite evidence from an earlier invocation.
    if metrics_path.exists():
        raise RuntimeError(f"metrics already exist: {metrics_path}")
    master, slave = pty.openpty()
    original_modes = termios.tcgetattr(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    os.set_blocking(master, False)
    command = list(args.command)
    if command and command[0] == "--":
        command.pop(0)
    command += [f"--metrics={metrics_path}", f"--records={args.records}",
                f"--history={args.history}", f"--burst={args.burst}"]
    if args.diagnostic:
        command.append("--diagnostic")
    env = {**os.environ, "TERM": "xterm-256color", "CINDER_FORCE_INTERACTIVE": "1"}
    child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                             env=env, start_new_session=True)
    samples = Samples(metrics_path)
    started = time.monotonic()
    tail = b""
    output_bytes = 0
    input_bytes = 0
    checkpoints = []
    last_heap_at = float("-inf")
    heap_path = destination / f"heap-{run:03d}.jsonl"
    heap_file = heap_path.open("w") if args.diagnostic else None

    def tick(wait=0.03, drain=True, allow_heap=True):
        nonlocal tail, output_bytes, last_heap_at
        readable, _, _ = select.select([master] if drain else [], [], [], wait)
        if readable:
            # Bound each drain turn so a fast producer cannot starve controls.
            for _ in range(16):
                try:
                    data = os.read(master, 65536)
                except BlockingIOError:
                    break
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output_bytes += len(data)
                tail = (tail + data)[-16384:]
        samples.poll()
        if samples.errors:
            raise RuntimeError(", ".join(samples.errors))
        now = time.monotonic()
        if (allow_heap and heap_file and samples.latest and samples.latest.get("vm_service_uri")
                and now - last_heap_at >= 30 and child.poll() is None):
            last_heap_at = now
            snapshot = heap_sample(samples.latest["vm_service_uri"])
            snapshot["elapsed_ms"] = int((now - started) * 1000)
            snapshot["rss_sample_bytes"] = samples.latest["rss_bytes"]
            heap_file.write(json.dumps(snapshot) + "\n")
            heap_file.flush()

    def send(data, drain=True):
        nonlocal input_bytes
        position = 0
        deadline = time.monotonic() + 10
        while position < len(data):
            if child.poll() is not None:
                raise RuntimeError("child exited while sending input")
            if time.monotonic() > deadline:
                raise TimeoutError("terminal input stalled for 10 seconds")
            try:
                written = os.write(master, data[position:position + 4096])
                position += written
                input_bytes += written
            except BlockingIOError:
                pass
            tick(0, drain=drain, allow_heap=drain)

    def wait_for(name, predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            tick()
            if samples.latest and predicate(samples.latest):
                checkpoints.append(name)
                return
            if child.poll() is not None:
                raise RuntimeError(f"child exited before {name}")
        raise TimeoutError(f"checkpoint failed: {name}; last={samples.latest}")

    def resize(columns, rows):
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        child.send_signal(signal.SIGWINCH)

    failure = None
    try:
        wait_for("rendered", lambda s: s["frames"] > 0, timeout=60)
        send(b"\x1b[F")
        wait_for("end selection", lambda s: s["selected_id"] == args.records - 1)
        send(b"\x1b[H")
        wait_for("home selection", lambda s: s["selected_id"] == 0)
        send(b"/payment\r")
        wait_for("search filter", lambda s: s["applied_query"] == "payment"
                 and s["visible_records"] == args.records // 4)
        resize(60, 12)
        wait_for("small resize", lambda s: s["width"] == 60 and s["height"] == 12)
        # One physical bracketed paste, large enough to expose parser/editor
        # retention failures, comfortably below the framework's input cap.
        send(b"/\x1b[200~" + ("🚀" * 20000).encode() + b"\x1b[201~\r")
        wait_for("large Unicode paste", lambda s: s["query_code_units"] == 256
                 and s["applied_query"].startswith("🚀") and s["active_searches"] == 0)
        cancelled = samples.latest["search_cancelled"]
        # Enhanced Escape removes the legacy 35ms ambiguous-escape timeout.
        send("/東京\r\x1b[27u".encode())
        wait_for("search cancellation", lambda s: s["search_cancelled"] > cancelled)
        send(b"/\x7f\r")
        wait_for("clear filter", lambda s: s["applied_query"] == ""
                 and s["visible_records"] == args.records)
        send(b"l")
        wait_for("live view", lambda s: s["show_live"] and s["live_records"] > 0)
        send(b"p")
        wait_for("producer pause", lambda s: not s["streaming"])
        send(b"p")
        wait_for("producer restart", lambda s: s["streaming"])
        resize(160, 48)
        wait_for("large resize", lambda s: s["width"] == 160 and s["height"] == 48)
        resize(100, 24)
        send(b"l")
        wait_for("archive recovery", lambda s: not s["show_live"] and s["width"] == 100)

        # Saturate terminal output with a full large viewport, then keep the
        # reader paused while commands and the live producer continue. Metrics
        # travel through the separate bounded JSONL file, so observing progress
        # cannot accidentally drain the blocked terminal.
        baseline = samples.latest
        stalled_keys = baseline["handled_keys"]
        stalled_records = baseline["ingested_records"]
        stall_started = time.monotonic()
        next_stall_input = stall_started
        while time.monotonic() - stall_started < 2.5:
            now = time.monotonic()
            if now >= next_stall_input:
                resize(160, 48)
                send(b"l\x1b[F\x1b[H", drain=False)
                next_stall_input = now + 0.1
            tick(drain=False, allow_heap=False)
        stalled = samples.latest
        if stalled["handled_keys"] <= stalled_keys or stalled["ingested_records"] <= stalled_records:
            raise RuntimeError("input or producer stopped during terminal output stall")
        checkpoints.append("input and producer progressed while output reader stalled")
        # Resume draining and recover a known archive/filter state.
        if stalled["show_live"]:
            send(b"l")
        send(b"/\x7f\r")
        wait_for("output stall recovery", lambda s: not s["show_live"]
                 and s["visible_records"] == args.records and s["width"] == 160)

        next_action = time.monotonic()
        action = 0
        stress_started = next_action
        # --seconds specifies sustained workload after functional checkpoints.
        while time.monotonic() - stress_started < args.seconds:
            now = time.monotonic()
            if child.poll() is not None:
                raise RuntimeError("child exited during sustained workload")
            if now >= next_action:
                if action % 40 == 0:
                    resize(60, 12)
                elif action % 40 == 20:
                    resize(160, 48)
                choices = [b"\x1b[6~", b"\x1b[5~", b"\x1b[F", b"\x1b[H",
                           b"/payment\r", b"/\x7f\r", b"l", b"l"]
                send(choices[action % len(choices)])
                action += 1
                next_action = now + 0.5
            stall = args.stall_ms and (now - stress_started) % 5 < args.stall_ms / 1000
            tick(drain=not stall)
        checkpoints.append("sustained workload")
        if heap_file:
            snapshot = heap_sample(samples.latest["vm_service_uri"])
            snapshot["phase"] = "after_stress"
            snapshot["elapsed_ms"] = int((time.monotonic() - started) * 1000)
            snapshot["rss_sample_bytes"] = samples.latest["rss_bytes"]
            heap_file.write(json.dumps(snapshot) + "\n")
            heap_file.flush()
        send(b"\x1b[27u")  # ensure the search field cannot consume q
        if args.shutdown == "q":
            send(b"q")
        else:
            child.send_signal(signal.SIGTERM if args.shutdown == "sigterm" else signal.SIGINT)
        deadline = time.monotonic() + 10
        while child.poll() is None and time.monotonic() < deadline:
            tick()
        if child.poll() is None:
            raise TimeoutError("application did not exit within 10 seconds")
        for _ in range(3):
            tick()
        if child.returncode != 0:
            raise RuntimeError(f"child exit code {child.returncode}")
        if termios.tcgetattr(slave) != original_modes:
            raise RuntimeError("termios modes were not restored")
        for sequence, name in [(b"\x1b[?1049l", "alternate screen"),
                               (b"\x1b[?25h", "cursor"),
                               (b"\x1b[?2004l", "bracketed paste")]:
            if sequence not in tail:
                raise RuntimeError(f"missing {name} restoration")
        if not samples.latest or not samples.latest["disposed"]:
            raise RuntimeError("no completed model-disposal sample")
        if samples.latest["retained_archive"] or samples.latest["live_records"]:
            raise RuntimeError("records retained after disposal")
        checkpoints.append("terminal and model restored")
    except Exception as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
        samples.poll()
        summary = {
            "event": "summary", "run": run, "ok": failure is None,
            "failure": failure, "command": command,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "sustained_seconds_requested": args.seconds,
            "shutdown": args.shutdown, "diagnostic": args.diagnostic,
            "checkpoints": checkpoints, "sample_count": samples.count,
            "rss_min_bytes": samples.rss_min, "rss_max_bytes": samples.rss_max,
            "rss_after_30s_first_bytes": samples.warm_rss_first,
            "rss_after_30s_last_bytes": samples.warm_rss_last,
            "input_bytes": input_bytes, "output_bytes": output_bytes,
            "exit_code": child.returncode, "last_sample": samples.latest,
        }
        if failure:
            (destination / f"failure-{run:03d}.terminal").write_bytes(tail)
        (destination / f"summary-{run:03d}.json").write_text(json.dumps(summary, indent=2) + "\n")
        samples.close()
        if heap_file:
            heap_file.close()
        os.close(master)
        os.close(slave)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=60, help="stress duration after checkpoints")
    parser.add_argument("--runs", type=int, default=1, help="sequential complete process lifecycles")
    parser.add_argument("--records", type=int, default=100000)
    parser.add_argument("--history", type=int, default=2048)
    parser.add_argument("--burst", type=int, default=64)
    parser.add_argument("--stall-ms", type=int, default=0, help="pause PTY draining every 5 seconds")
    parser.add_argument("--shutdown", choices=("q", "sigterm", "sigint"), default="q")
    parser.add_argument("--diagnostic", action="store_true", help="JIT VM-service forced-GC heap sampling")
    parser.add_argument("--output", required=True, help="new result directory")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="-- /path/to/compiled-app")
    args = parser.parse_args()
    if not args.command:
        parser.error("supply app command after --")
    if args.seconds < 0 or args.runs < 1 or args.records < 4 or args.records % 4:
        parser.error("seconds >= 0, runs >= 1, records divisible by 4 and >= 4 required")
    if not 0 <= args.stall_ms <= 2000:
        parser.error("stall-ms must be 0..2000")
    for run in range(args.runs):
        summary = run_session(args, run)
        print(json.dumps(summary), flush=True)
        if not summary["ok"]:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
