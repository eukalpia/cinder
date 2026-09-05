# Native terminal transport

`PtyController` supports macOS/Linux PTYs and Windows ConPTY (Windows 10 1809+
/ Windows Server 2019+). The native implementation uses the existing `ffi`
dependency and works with Dart 3.9.4. The web conditional implementation reports
that browsers cannot create local operating-system terminals.

On Unix, `/usr/bin/script` owns terminal allocation, the child session, signal
handling, and child reaping through `dart:io Process`. A fixed startup shell sets
rows/columns using `stty` before executing literal argv. It writes the terminal
path and child PID to a private temporary directory, separate from application
input/output. It waits for a private acknowledgement before exec so Cinder owns
the terminal descriptor and session identity even for immediately exiting commands. Cinder opens the terminal with `O_NOCTTY` and uses `TIOCSWINSZ` for
live resize. The startup directory and terminal descriptor are released promptly
on exit, including failed launches. Unix also requires `/bin/sh`, `/bin/stty`,
`/usr/bin/tty`, `/bin/sleep`, and `/bin/ps`, normally provided by the supported systems.

Shutdown queries the private terminal's members asynchronously before signaling
its owner, including foreground job groups. On natural exit, cleanup checks all
process IDs for surviving members of this session, since their terminal
association may already be gone. Session membership is checked before
signals, and remaining known members are terminated promptly on transport exit.
Numeric process IDs are not retained for signaling during a later disposal.
Processes that deliberately detach into another session are outside this PTY.
Only one signal operation runs at a time; duplicate concurrent requests return
false while a single SIGKILL escalation can remain pending.
Unix signal exit codes follow the platform's `script` utility: for example, a
child killed by SIGTERM reports 15 on macOS and 143 with util-linux. `pid` identifies
the transport process. Normal numeric child exit codes are preserved.

On Windows, `CreatePseudoConsole` and `ResizePseudoConsole` manage the terminal.
Child startup explicitly requests fresh console standard handles so redirected
host input/output cannot bypass ConPTY.
UTF-16 process arguments use Microsoft CRT quoting, and environment overrides
are case-insensitive. Synchronous pipe writes and `ClosePseudoConsole` run on
worker isolates while the main isolate drains output. Disposal waits for output
EOF and the active write before releasing handles. Output includes ConPTY's
terminal control sequences; history is raw output, not a rendered screen.

History defaults to 10,000 lines and 8 MiB of encoded UTF-8. Each completed newline
costs one byte. An oversized line retains its newest complete UTF-8 characters;
callbacks still receive all output. Queues and geometric chunk compaction avoid
shifting the full history or copying a growing unterminated line on every append.
Pending input is capped at 1 MiB or 256 writes. A full queue rejects the new write
with `StateError`; disposal cancels queued input. Unix stream subscriptions pause
at 256 KiB of queued transport output and resume below 128 KiB.

The transport polls ready output every 4 ms with a per-turn read limit so active
terminals yield to UI/input. Windows creates a worker isolate per accepted write.
These choices favor a bounded, portable implementation; they are not an evented
native I/O implementation or a claim of measured PTY throughput.

API references: [Windows pseudoconsole creation](https://learn.microsoft.com/en-us/windows/console/createpseudoconsole),
[resize](https://learn.microsoft.com/en-us/windows/console/resizepseudoconsole),
[shutdown and output drainage](https://learn.microsoft.com/en-us/windows/console/closepseudoconsole),
and [Windows argv parsing](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments).
