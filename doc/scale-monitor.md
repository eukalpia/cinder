# Scale monitor

`example/scale_monitor.dart` is a working operations console with 100,000
deterministic archive records, a live log feed, Unicode text, search, selection,
and resize support. Run it from the repository root:

```sh
dart run example/scale_monitor.dart
```

Use arrows, Page Up/Down, Home and End to select rows. `/` focuses the search
field and selects its current text; Enter applies the archive filter. Escape
cancels unfinished search. `l` switches archive/live views; `p` pauses or resumes
the producer; `q` shuts down and restores the terminal. Search matches service,
severity, message or record ID without case sensitivity. Live view follows the
newest retained record; filtering returns to archive view.

## Resource and work contracts

| Resource or operation | Bound |
| --- | --- |
| Archive | Fixed record count, default 100,000; allocated once |
| Live feed | Fixed ring, default 2,048 records; oldest records evicted |
| Input query | At most 256 UTF-16 code units; surrogate pairs preserved |
| Active search | One task, one latest pending query |
| Search results | One committed and at most one in-progress `Uint32List`, each at most archive length |
| Task diagnostics | Eight completed task snapshots |
| Search scheduling | At most 512 records examined before yielding to the event loop |
| Row construction | `ListView.builder(lazy: true, itemExtent: 1, cacheExtent: 2)`; viewport plus a small cache |
| Stream notifications | One microtask notification for a synchronous event burst |
| Producer | One periodic timer, default 64 records every 50 ms |
| Metrics | Scalar counters, nine fixed frame-time buckets, one JSONL sample per second |

Storage intentionally grows with the configured archive size. Search examines
that archive after explicit submission; ordinary frames neither scan nor copy
it. Record messages and services are deterministic shared strings, so this
workload measures a large object/index dataset rather than pretending that
100,000 unique long log messages have the same memory cost. Search matching
allocates temporary lowercase strings; the reference does not retain a search
cache for every record or past query.

Superseding a search replaces the pending slot and invalidates the active scan.
A stale scan cannot commit. Disposal cancels the producer, requests cooperative
search cancellation, waits for cleanup, releases archive/ring/index storage and
removes listeners. A terminal smaller than six rows displays a compact resize
message; the controls still allow quitting.

## Repeatable native stress

Build once before running any measured workload. The build wrapper embeds a
source SHA-256, verifies that Dart sources did not change during compilation,
and writes binary/archive hashes, Git revision/dirty status, and a source tarball beside
the executable. The tarball includes LICENSE and NOTICE.md; snapshot file hashes
are checked again after compilation. Keep all three artifacts with results.

```sh
python3 benchmark/runtime_scale/build.py --dart dart \
  --output /tmp/cinder-scale-build/scale-monitor
python3 benchmark/runtime_scale/run_stress.py \
  --seconds 7200 --output /tmp/cinder-scale-two-hours \
  -- /tmp/cinder-scale-build/scale-monitor
```

The Python driver uses only the standard library and a real Unix PTY. It runs
functional checkpoints first, then the requested sustained duration. Checkpoints
verify atomic keyboard bursts, Home/End selection, filter results, an 80 KB
Unicode bracketed paste, cancellation, 60×12 and 160×48 resize, producer pause and
restart, and recovery after pausing terminal output consumption for 2.5 seconds.
During that output stall, it checks that input and producer counters advance
using the separate metrics file. At completion it checks exit status, exact
termios restoration, terminal cleanup sequences, and model disposal.

The sustained workload repeats navigation, filter changes, live/archive
switches and resize. The driver drains output, retaining only the final 16 KiB
for failure diagnostics. It reads metrics incrementally and fails on observed
history/query/search/task-history/row-work cap violations or reported framework
errors. It does not infer successful cleanup from a zero exit code alone.

Additional modes:

```sh
# Repeat complete process lifecycles; each run has separate evidence.
python3 benchmark/runtime_scale/run_stress.py --seconds 30 --runs 3 \
  --shutdown sigterm --output /tmp/cinder-scale-restarts \
  -- /tmp/cinder-scale-build/scale-monitor

# Also stop draining the PTY for 750 ms every five seconds during the workload.
python3 benchmark/runtime_scale/run_stress.py --seconds 300 --stall-ms 750 \
  --shutdown sigint --output /tmp/cinder-scale-stalls \
  -- /tmp/cinder-scale-build/scale-monitor
```

`--seconds` excludes initial checkpoints and final cleanup. Each result directory
must be new: the runner refuses to overwrite existing run evidence. Default
archive/history/producer settings can be changed with `--records`, `--history`
and `--burst`; runner record counts must be divisible by four so its filter
checkpoint has an exact independent expected count.

`run-NNN.jsonl` contains process RSS/current peak RSS, runtime identity, source
fingerprint, live/evicted counts, active/pending searches, retained archive size,
row constructions, notifications, handled keys, viewport dimensions, completed
search timings, frame count/summed/max duration, and a fixed frame histogram.
`summary-NNN.json` contains checkpoint outcomes, aggregate RSS extrema, RSS
endpoints after 30 seconds, total input/output bytes, and the final sample.
Machine-readable output is streamed to disk, so disk usage grows with duration;
the app and runner do not keep the full sample history in memory.

Frame timings measure Cinder scheduler work. They exclude time spent waiting
for a terminal to consume output and are not end-to-end key latency. The JSONL
sampler performs synchronous file writes once per second to prevent an output
queue from growing; measurements include that overhead. A long run performed
while other builds/tests are active provides resource/lifecycle evidence. Use a
separate quiet serial run for CPU or timing comparisons.

## Separate JIT heap diagnostics

AOT RSS includes the runtime, application, native allocations, executable pages,
allocator capacity and thread stacks. It is not Dart live-heap size. The JIT
compiler and VM service add substantial overhead, so keep diagnostics separate:

```sh
python3 benchmark/runtime_scale/run_stress.py --diagnostic --seconds 60 \
  --output /tmp/cinder-scale-heap \
  -- dart --disable-dart-dev example/scale_monitor.dart
```

This opens the Dart VM service locally and records `getAllocationProfile` with
explicit GC, followed by `getMemoryUsage`, at startup, every 30 seconds and after
the sustained workload. `heap-NNN.jsonl` records managed heap usage/capacity,
external usage, the top 20 classes by live shallow bytes, a nearby RSS sample,
and a class-name inventory of direct app objects, direct buffer objects,
typed-data storage and remaining managed objects.

These class groups provide attribution clues rather than ownership graphs.
For example, `ScaleRecord` identifies archive/live record objects; shared
backing lists and typed arrays cannot be assigned exclusively to the app or
renderer from an allocation profile. The gap between RSS and managed/external
heap is not an exact measurement of VM overhead: heap capacity, committed and
resident pages, shared libraries, native allocations and fragmentation differ.
Do not mix JIT profile RSS with AOT process RSS, and do not use forced-GC frame
timings as normal workload timings. Diagnostics are rejected by the AOT app.

## Automated regression checks

```sh
dart test test/integration/scale_monitor_test.dart test/focus \
  test/components/text_field_focus_test.dart
python3 -m unittest discover -s benchmark/runtime_scale -p 'test_*.py'
```

The integration tests exercise row construction and mounted-row bounds at both
1,000 and 100,000 records, ring eviction and burst coalescing, superseded and
cancelled searches, long Unicode input, native Enter at the query limit, and
producer/search disposal. They also cover the production focus regression found
by the PTY run: focus acquisition and release must affect subsequent events in
the same physical input burst, before the next frame rebuild.

This document defines the workload and commands; it makes no unmeasured
performance claims. Preserve generated evidence before drawing conclusions
about hours-long memory behavior or comparing frameworks.
