# Terminal application comparison

The default `rc2` suite compares persistent terminal applications displaying the same
precomputed text through a real PTY. They measure application CPU, resident
memory, emitted ANSI bytes, and keyboard-to-output latency with normal frame
pacing. They do not measure maximum rendering throughput.

The [RC2 measurement report](https://github.com/eukalpia/cinder/releases/download/v1.0.0-rc.2/cinder-benchmark-macos-arm64.md)
records the complete macOS arm64 comparison, trial variation, resource usage,
and its limits. Its [raw evidence archive](https://github.com/eukalpia/cinder/releases/download/v1.0.0-rc.2/cinder-benchmark-macos-arm64.tar.gz)
contains the trial JSON and ANSI captures, toolchain configuration, workload
order, and matching source snapshot.

The default matrix uses a 120-column × 40-row terminal, a 60 FPS cap, three
independent process runs per adapter and workload, a six-second settling period,
30 warmup updates, and 180 measured updates. All applications use their normal
stdin/stdout backend. OpenTUI retains its native Zig renderer and the platform's
normal output threading.

The comparison pins Ink 7.1.1, React 19.2.4, OpenTUI 0.5.10, and Bubble Tea 2.0.9
in the checked-in dependency files. The reference toolchains are Dart 3.13.3
with AOT compilation, Node 24.20.0, Bun 1.4.0, and Go 1.27.1. `prepare.py` records
the toolchain versions actually used; it does not install or enforce those
versions. Use the same Dart executable and dependency lockfile for both Cinder
revisions.

Run the following from the repository root on macOS or Linux, with the selected
toolchains on `PATH`:

```sh
python3 -m venv benchmark/comparison/.venv
benchmark/comparison/.venv/bin/python -m pip install -r benchmark/comparison/requirements.txt

benchmark/comparison/.venv/bin/python benchmark/comparison/prepare.py \
  --baseline v1.0.0-rc.1

benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands benchmark/comparison/bin/commands.json \
  --output benchmark/comparison/results/local \
  --width 120 --height 40 --fps 60 \
  --rounds 3 --settle-seconds 6 --warmup 30 --frames 180

benchmark/comparison/.venv/bin/python benchmark/comparison/summarize.py \
  benchmark/comparison/results/local \
  > benchmark/comparison/results/local/summary.md
```

`prepare.py` also accepts `--dart`, `--node`, `--bun`, `--go`, and `--npm` paths,
plus `--output` for build artifacts. It builds the current Cinder source and the
selected baseline with the same adapter, installs the locked JavaScript
dependencies with `npm ci`, and builds Bubble Tea before measurement. Its
configuration records commits, source hashes, and whether the working tree was
dirty. Preserve the matching source snapshot when reproducing a dirty build.

Use an empty results directory for each experiment; the matrix rejects existing
contents. Finish builds and dependency
installation first, and keep other builds or benchmarks idle while the matrix
runs. The matrix runs serially with a reproducible shuffled order. Retain its
configuration, matrix settings, order, individual JSON results, and ANSI
captures. `summarize.py` requires the complete trial set; a failed run is not a
zero-valued result. Failure evidence is saved as `.failure.json`,
`.failure.stderr`, and `.failure.ansi`. Four-frame smoke checks establish
correctness only.

Each frame contains 4,800 printable ASCII cells arranged as 40 rows separated by
39 newlines, with no trailing newline. The adapters load two strings before
measurement, show the first at startup, advance to the other on a real `n` key,
and exit on `q`.

| Workload | Change between the two text states |
| --- | --- |
| `sparse` | One cell near the center changes. |
| `dense` | Every visible cell changes. |
| `scroll` | Rows rotate by one position, then return on the next update. |

Every update supplies the complete precomputed string. String generation and
file loading are outside the measured interval. The `scroll` case is a text-row
rotation, not a scroll widget, wheel-input test, or large-document viewport.
This small two-state workload does not establish behavior for Unicode,
wrapping, styled spans, animations, large widget trees, or long-lived heaps.

Cinder uses `Focus`, state updates, and `Text`; Ink uses React state and a
`Box`/`Text` tree with `incrementalRendering: true`; OpenTUI updates a retained
`TextRenderable`; Bubble Tea returns the string through its normal model/View
API. These are normal application paths with different amounts of layout and
reconciliation work. Bubble Tea's adapter does not add a separate text widget or
layout tree. Ink's incremental rendering option is explicit and differs from
its default configuration. No adapter calls a private render loop, forces a
flush on measured input, or replaces native output with a counting sink.

The driver advertises the same terminal dimensions, truecolor environment, and
synchronized-output support. After the initial grid it drains and answers
terminal queries for six seconds, then performs the warmup updates. This common
settling period covers [OpenTUI's five-second startup capability window](https://github.com/anomalyco/opentui/blob/v0.5.10/packages/core/src/renderer.ts#L3286-L3304); it does
not prove that every runtime has reached a universal JIT or GC steady state.

One key is outstanding at a time. The next key is sent after the previous
screen has been decoded, checked, and sampled. Every expected grid must match
all character cells; once synchronized-output markers are observed, completion
also requires a new closing marker. Latency timestamps use receipt of the
completing PTY chunk, before decoding that chunk. They include framework pacing,
input handling, output, OS scheduling, and driver wakeup. They do not measure
pixels presented by a terminal emulator. Decoding and sampling delay the next
key and change its phase relative to each frame scheduler, so a lower latency
here does not by itself establish a faster renderer or general input latency.

Character equality does not establish equality of colors, attributes, cursor
state, or scrollback. OpenTUI's default text emits an explicit white foreground;
the other adapters retain the terminal's default foreground. The driver's
advertised defaults are white on black. ANSI byte counts include each
framework's normal style, cursor, synchronization, and diff encoding, rather
than an identical-style serialization algorithm. Shutdown must succeed and
restore terminal input modes; Darwin's kernel-managed `PENDIN` flag is recorded
separately. Ink's exact cursor-restoration escape on stderr is permitted and
recorded; other stderr content fails the run.
The JSON `terminal_cleanup` fields record observed alternate-screen exit and
cursor-show sequences; these are sequence-presence metadata, not a full terminal
state equivalence check.

| Measurement | Interpretation |
| --- | --- |
| CPU ms/frame | Application PID user plus system CPU delta divided by measured updates. Includes its native threads and runtime work; excludes the Python driver and session host. It is not render-only duration or wall latency. |
| RSS MiB | Resident memory sampled after completed updates, including the runtime and native allocations in the application process. It is not managed heap size, allocation volume, or memory added by one frame. |
| Maximum observed RSS | Largest post-frame sample. Brief peaks between samples can be missed; this is not an OS high-water mark. |
| Bytes/frame | Measured stdout ANSI bytes divided by updates, excluding startup, warmup, and shutdown. It is not SSD traffic. |
| Latency percentiles | PTY input-to-completing-output observations under this closed-loop, capped arrival pattern. The summary takes the median of each trial's percentile, not a percentile of pooled samples. |

New runs record `startup_timestamp_clock: clock_gettime_ns(CLOCK_MONOTONIC)`.
Startup spans the session host's application launch and the driver's receipt of
the initial verified screen, so both timestamps must use a shared clock origin.
Earlier results without that field used `perf_counter_ns` across processes;
on Python 3.9/macOS its origins differ and those `startup_ms` values are invalid.
Published RC2 artifacts remain unchanged. This correction does not change the
closed-loop measured latency, CPU, or RSS definitions, and startup is not
included in the comparison summary.

The summary reports medians across independent trials and the full CPU range.
Keep trial variation visible, especially for tail latency from short runs.
Resident memory includes shared code and native-library pages and does not
aggregate separate descendant processes. This workload performs no deliberate
disk writes during updates; that alone does not establish zero disk I/O. Use
the individual result's `process_io` entry: `supported: true` includes measured
`read_bytes`, `write_bytes`, `read_count`, and `write_count` deltas;
`supported: false` includes the reason counters were unavailable. The Markdown
summary does not include these counters. Such counters are platform-defined
process statistics, not
direct measurements of physical SSD traffic, cache misses, or device wear.

Installation footprint is a separate experiment. Report compiled application
file sizes, required runtime and production dependencies, and development/cache
directories separately. A Cinder or Bubble Tea executable includes its runtime
in a different form from a JavaScript adapter requiring Node or Bun and native
packages. The shared `javascript/node_modules` directory contains dependencies
for both JavaScript adapters and cannot be attributed wholesale to either one.
Use isolated production installations for per-adapter totals, distinguish
logical file bytes from allocated disk blocks, and exclude SDKs, build caches,
source trees, and benchmark results from an application-artifact comparison.

## Expanded comparison and data workflow

The optional suites add Ratatui 0.30.2 with Crossterm 0.29.0, FTXUI 6.1.9, and
Textual 8.2.8. They are separate experiments from the published RC2 report;
adding adapters or changing the workload does not revise that report's results.
`prepare.py --extended` preserves the original five `adapters` commands and
also writes `extended_adapters` (eight commands including the Cinder baseline)
and `data_adapters` (seven frameworks, current Cinder only).

Ratatui and all Rust transitive dependencies are locked by `Cargo.lock`, built
with `cargo build --release --locked`. FTXUI is fetched from the official
repository at commit `5cfed50702f52d51c1b189b5f97f8beaf5eaa2a6`; its archive
and nlohmann/json 3.12.0 have SHA-256 checks in `ftxui/CMakeLists.txt`. Textual
and its Python dependencies are pinned with hashes in
`textual/requirements.lock` and installed in a separate virtual environment.
Preparation records actual compiler/interpreter versions, Cargo metadata,
installed Python packages, build settings, source and executable hashes, and
compiled-file logical/allocated sizes. These file sizes exclude dynamic system
libraries and the separate Node, Bun, and Python runtime/dependency trees.
They are not total installation-footprint comparisons.

Reference additional tools used for correctness validation are Rust/Cargo
1.98.0, Apple Clang 17.0.0, CMake 4.2.0, and Python 3.9.6. Preparation records
these tools but does not install or enforce their versions. Supply `--cargo`,
`--rustc`, `--cmake`, `--cxx`, and `--python` to select others. The Python lock
was resolved for Python 3.9; all locked packages must support the interpreter
selected. Build jobs default to four and are configurable with `--build-jobs`.

```sh
# Build before measuring; the output should be outside saved RC2 evidence.
benchmark/comparison/.venv/bin/python benchmark/comparison/prepare.py \
  --extended --baseline v1.0.0-rc.2 --output /tmp/cinder-comparison-build

# Correctness smoke: two complete 24-key action cycles; ignore timing values.
benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands /tmp/cinder-comparison-build/commands.json \
  --suite data --records 50000 --rounds 1 --warmup 0 --frames 48 \
  --settle-seconds 6 --output /tmp/cinder-data-smoke

# Separate serial trials, after all builds/tests and competing jobs are idle.
benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands /tmp/cinder-comparison-build/commands.json \
  --suite data --records 50000 --rounds 3 --warmup 48 --frames 192 \
  --settle-seconds 6 --output /tmp/cinder-data-trials

# The original text states with all additional adapters:
benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands /tmp/cinder-comparison-build/commands.json \
  --suite expanded-grid --output /tmp/cinder-expanded-grid-trials
```

`summarize.py` accepts each of these result directories separately. Never pool
different suites, record counts, viewport sizes, scheduler settings, or action
mixes. A four-frame data smoke is insufficient: it does not reach search, sort,
filter, or append. The 48-frame smoke exercises all operations twice. The suite
defaults to one real key outstanding at a time. The separate fixed-arrival
mode below measures overload responsiveness with the same scheduler settings.
Neither mode measures uncapped rendering throughput.

The `workspace-v1` input contains 50,000 structured records by default, plus a
deterministic action sequence. It contains no expected screen strings. All
seven applications retain those records, handle actual `j/k/p/g/G/x/f/e/s/a`
keys, maintain cursor and selection state, scan data for search and filtering,
sort matching records, append new records, maintain three recent event-log
entries, and format only visible table rows. At 120 × 40 the viewport holds 32
table records, three header rows, a log heading, three log entries, and a key
legend. Dataset creation and JSON loading happen before readiness; model
actions and viewport formatting happen after input inside the measured process.
See [the complete model contract](DATA_WORKLOAD.md).
Ink's public input callback can deliver several printable keys together; its
data adapter applies each key in order and requests one React update per batch.

The driver computes its expected screens before starting the application,
then verifies every visible character after every action. The visible step
number prevents unchanged/clamped actions from satisfying completion with an
old screen. Tests additionally assert selection persistence, sorted/filtered
record contents, bottom-of-data scrolling, appended-record contents, and
viewport dimensions. Textual shares the Python model with the driver oracle;
its model correctness therefore also depends on these direct behavioral tests.
The other languages use independent ports checked against the same oracle.

This is an application workload with a common manual viewport, not a comparison
of each framework's native table or list widget. Cinder, Ink, OpenTUI, and
Textual use their normal text widgets; Ratatui uses `Paragraph`; FTXUI creates
a `vbox` of visible `text` elements; Bubble Tea returns a View string. The apps
implement equivalent features and output, while their widget/reconciliation
work differs. The application data representations are explicit:

| Adapter | Resident records | Matching collection |
| --- | --- | --- |
| Cinder / Dart | Immutable typed `WorkspaceRecord` objects, decoded from JSON at startup | References to those objects |
| Ratatui / Rust | Typed `Record` structs in a vector | Record indexes |
| FTXUI / C++ | Typed `Record` structs in a vector | Record indexes |
| Bubble Tea / Go | Typed `record` structs in a slice | Copies of matching structs |
| Ink and OpenTUI / JavaScript | Plain objects decoded from JSON | Object references |
| Textual / Python | Dictionaries decoded from JSON | Dictionary references |

Dart decodes fields once before readiness rather than retaining JSON maps for
repeated lookup and casting during actions. This is an adapter/model setup
change, not a Cinder framework-core optimization. Every rebuild still scans the
records, constructs and lowercases the same search string, applies the same
filters, and sorts matches when requested. No search or sort results are cached.
Selection, append, and viewport formatting retain the same work and semantics.
The typed model and its freshly compiled data executable have different source
and artifact identities from earlier Dart map-based data runs; keep those results
separate. CPU and RSS include application model and runtime costs, so they cannot
isolate a universal renderer ranking.

Ratatui's normal application loop uses
[`Terminal.draw` and Crossterm input](https://ratatui.rs/tutorials/counter-app/_multiple-files/event/).
Its application caps draw starts at the requested FPS. FTXUI uses
[`ScreenInteractive`, `Renderer`, and `CatchEvent`](https://github.com/ArthurSonzogni/FTXUI/tree/v6.1.9);
its public Renderer callback applies an application minimum frame period.
Neither library has an equivalent automatic max-FPS scheduler setting.
Textual uses [`Static.update`](https://textual.textualize.io/widgets/static/)
and [`TEXTUAL_FPS`](https://textual.textualize.io/api/constants/).
The other four retain the documented scheduling configuration above. A common
upper cap does not mean identical scheduling or input phases. No adapter calls
a private renderer/flush or bypasses its terminal backend on input.

Textual's official
[`LinuxDriver` renders to stderr](https://github.com/Textualize/textual/blob/v8.2.8/src/textual/drivers/linux_driver.py).
For this adapter the driver connects stderr to the same PTY and captures stdout
as its diagnostic stream; all other adapters use stdout for the PTY. This is
recorded in `terminal_output_descriptor` and `diagnostic_descriptor`. The
`.failure.stderr` filename is retained for compatibility and contains that
diagnostic stream. ANSI bytes refer to the selected terminal-output descriptor.
Textual emits explicit white-on-black truecolor styles. Character parity still
does not establish exact attribute or ANSI-encoding parity.

Each measured update records its input key, step, input-write timestamp,
completing PTY-chunk receipt timestamp, subsequent screen-verification and RSS
sample timestamps, stream byte offsets, and synchronization-marker counts.
For `workspace-v1`, completion also rejects a still-open synchronized update,
including a new open after an older close in the same read chunk. For adapters
without synchronized output, character equality establishes receipt of the
visible screen but cannot identify later cursor/style-control bytes. Those
bytes may belong to the next observed byte interval. A PTY read can coalesce
writes, and receipt timing includes OS scheduling and driver wakeup. These
are observable terminal-stream boundaries, not internal render durations,
terminal-emulator presentation times, or exact frame allocation counters.

## Fixed-arrival state visibility

For the data suite, `--arrival-interval-ms 4` or `20` sends predetermined keys
at nominal 250 or 50 inputs/second independently of received frames. The seven
adapters retain their normal APIs and configured 60 FPS caps. An independent
Python sender process waits until each nominal arrival and writes one ASCII
key. Its telemetry pipe is nonblocking: slow Python screen decoding cannot
block input delivery through that pipe. OS scheduling and PTY backpressure can
still delay actual sends; every event records its nominal arrival, actual write
start, write completion, and send lateness. All processes use
`clock_gettime_ns(CLOCK_MONOTONIC)` so timestamp origins agree even on macOS
with Python 3.9. The sender and driver are excluded from application CPU.

```sh
# Correctness only; repeat with 20 in a separate empty output directory.
benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands /tmp/cinder-comparison-build/commands.json \
  --suite data --records 50000 --rounds 1 --warmup 24 --frames 48 \
  --settle-seconds 6 --arrival-interval-ms 4 --event-deadline-ms 5000 \
  --output /tmp/cinder-arrival-4ms-smoke

# Separate longer trials, only during an otherwise quiet measurement window.
benchmark/comparison/.venv/bin/python benchmark/comparison/run_matrix.py \
  --commands /tmp/cinder-comparison-build/commands.json \
  --suite data --records 50000 --rounds 3 --warmup 48 --frames 192 \
  --settle-seconds 6 --arrival-interval-ms 4 --event-deadline-ms 5000 \
  --output /tmp/cinder-arrival-4ms-trials
```

Readiness, settling, and warmup remain closed loop. Before launch the driver
precomputes every oracle screen; measured time contains no oracle model updates.
Every observed synchronized-output close is checked separately, even when one
PTY read contains multiple frames. Its monotonic step and every visible cell
must equal the oracle. Without synchronization markers, a complete exact screen
is recognized after a PTY read; partial reads may continue until a match. Such
reads can merge application presentations, so the driver cannot count every
unsynchronized frame or prove when its final cursor/style controls finish.

For input step *i*, **state-visibility latency with coalescing** is the interval
from its actual input write start to receipt of the first PTY chunk whose
verified complete screen represents a step at least *i*. The screen verification
timestamp is recorded separately; the reported latency uses completing-chunk
receipt, before decoding, as in the closed-loop driver. The same observation
can cover several input steps. This says the application processed those actions
by a later visible state; it does not say each intermediate state was presented.
The final screen must exactly match the final model step and every key must have
a delivery trace. A mismatch, regressing complete step, missing final state,
unrestored terminal modes, or an actual-send visibility deadline miss fails the
trial and preserves diagnostics.

`state_visibility` records every input, observed step, actual-send and nominal
arrival latency p50/p95/p99, send-lateness p50/p95/p99, nominal deadline misses,
and `unobserved_intermediate_states`. That last count means application-coalesced
or driver-unobserved presentations; it is not a count of dropped input events.
The default 5,000 ms per-event deadline is measured from actual send. The sender
also fails if a key cannot be delivered within that duration of its nominal
arrival. Arrival rates are targets; consult actual send lateness before using a
run as evidence of sustained offered load.

`summarize.py` keeps these trials separate and reports CPU and ANSI bytes per
delivered input, resident memory sampled after observed states, both latency
distributions, send lateness, and the unobserved-state percentage. It validates
all final states and delivery counts before emitting a table. A short smoke
does not establish reliable tail percentiles. This mode measures responsiveness
and coalescing under fixed arrivals; async frame phases, public widget/model
costs, driver observation overhead, and different scheduling policies preclude
an instantaneous per-frame fairness or general renderer ranking.

Run the untimed harness/model regressions with:

```sh
benchmark/comparison/.venv/bin/python -m unittest discover \
  -s benchmark/comparison -p 'test_*.py'
```

With Dart on `PATH`, these tests also compare every visible cell, the complete
selection set, and resident record count against the Python oracle across two
24-key cycles with 50,000 records. They verify that mutating decoded source maps
cannot change the Dart model. Set `CINDER_BENCHMARK_DART` to select a specific
SDK; without Dart that direct parity test is explicitly skipped. The helper
`workspace_model_probe.dart` is used only by untimed tests, never by an adapter.
