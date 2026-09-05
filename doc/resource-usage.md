# CPU, memory, and deployment size

Use the [terminal comparison](../benchmark/comparison/README.md) to measure a
complete application on your target machine. Its CPU, resident memory, and
output-byte measurements have different boundaries; terminal output bytes are
not SSD writes. The included two-state ASCII grids are a starting point. Also
measure your application's Unicode text, widget tree, images, and long-running
state before setting resource budgets.

For native deployment, use [`cinder build`](building.md) to build an AOT
executable with separate debugging symbols by default. It includes the Dart runtime;
the target machine does not need a Dart SDK or your source/build directories.
See Dart's [executable and AOT module documentation](https://dart.dev/tools/dart-compile#self-contained-executables-exe).

```sh
cinder build bin/main.dart --output build/release/app
```

Keep the matching symbols with your release's diagnostic artifacts. Deploy the
executable and the application's required assets; symbols are not needed for
normal execution. The compiler option moves debugging information to the
separate file without changing application logic. Do not distribute SDKs,
`.dart_tool`, package caches, site dependencies, or benchmark results as part
of a native application.

When shipping multiple Dart applications for the same target, separate AOT
modules can share one compatible `dartaotruntime` instead of embedding a runtime
in every executable. Build modules and retain the runtime from the same SDK:

```sh
dart compile aot-snapshot bin/main.dart \
  --save-debugging-info=build/symbols/app.symbols \
  -o build/release/app.aot
dartaotruntime build/release/app.aot
```

This saves duplicated runtime storage across applications. It is a different
distribution layout, not an additional rendering optimization. Applications
using native build hooks need Dart's build workflow and their required native
assets; follow the compiler's diagnostics for those dependencies.

Cinder's normal frame renderer writes to the terminal rather than a frame log
on disk. The native log server keeps history in memory, streams to connected
clients, and creates a small discovery file at startup that is removed at
shutdown. Application code and dependencies can perform additional I/O.

Log history defaults to at most 10,000 entries and a conservative 1 MiB message
storage budget, counting two bytes per UTF-16 code unit. The oldest entries are
evicted when either limit is exceeded. A message larger than the whole budget
still streams to connected clients but is omitted from history. Configure
`LogServer(maxBufferBytes: ..., maxBufferSize: ...)` for a manually managed log
server; a zero byte budget disables retained history. This budget excludes
entry metadata, temporary JSON, client output queues, and caller-held snapshots.

Client output has separate defaults: at most 16 connections, 1,024 pending
messages and 2 MiB of encoded JSON string storage per client (two bytes per UTF-16
code unit, including the in-flight message). Set `maxClients`,
`maxPendingClientMessages`, and `maxPendingClientBytes` on `LogServer` to change
these limits. A client that exceeds a limit is disconnected; reconnecting replays
the available bounded history. Replay encodes one message at a time and retains
its own bounded history snapshot. Socket and kernel buffers are additional.

Native rendering uses nonblocking output and waits for the preceding batch to
drain before rendering another frame. This prevents a slow terminal from retaining
an ever-growing frame queue. Low-level application calls that write directly to
`Terminal` or a backend remain the application's responsibility. Output completion
means acceptance by the underlying consumer, not physical screen presentation.

The input parser uses bounded byte storage and consumes prefixes without shifting
the remaining packet per key. Processing yields after 256 dispatched events,
16 KiB of consumed input, or 8 ms of synchronous work, including queued small
packets. A single application callback must still return before yielding.
This allows frames, output completion, timers and cancellation to progress.
Large consumed paste allocations
are released rather than retained indefinitely by an idle parser.
Transport delays preserve incomplete Unicode, escape sequences and pastes.
Only a standalone Escape byte uses an ambiguity timeout. OSC responses share
the same bounded parser, so replies can span packets and pasted OSC text stays
inside the paste. Terminators follow the
[xterm control sequence specification](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
Shell-protocol OSC 9999 resize reports require positive dimensions of at most
4096 columns/rows and at most 1,000,000 total cells before notifying a backend.
Invalid reports are ignored. This protocol limit does not change host resize APIs.

The embedded `TerminalXterm` emulator has separate bounds: incomplete CSI/OSC
payloads are limited to 8 KiB of encoded UTF-8 and parsed incrementally; consumed
chunks are released after each write. Oversized sequences are discarded through
their terminator. Child window-resize commands are ignored because the containing
application controls the viewport. A REP command repeats at most the current
viewport's column count times row count; ordinary wrapping remains enabled.
These are explicit compatibility limits, documented with the
[vendored emulator changes](../lib/src/third_party/xterm_pure.dart/CINDER_CHANGES.md).
They do not bound the caller's current chunk or the rendered scrollback, which
remains separately controlled by `maxLines` and the host's viewport dimensions.

Use the [scale monitor](scale-monitor.md) for large virtualized collections,
bounded streaming history, cancellable searches and sustained PTY validation.

Repaint boundaries can retain buffers to reduce repaint work, so use them for
subtrees whose updates are independent. Adding boundaries everywhere can
increase retained memory. For large collections, prefer Cinder's virtualized
list and table components, and keep application histories and decoded images
bounded by their actual use.
