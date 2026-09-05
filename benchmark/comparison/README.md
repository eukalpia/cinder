# Terminal application comparison

These adapters compare persistent terminal applications displaying the same
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
