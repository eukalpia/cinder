# Renderer performance contract

Performance claims are valid only for a named workload, viewport, runtime mode, terminal/backend, and commit. Targets here are **1.0 release goals**, not claims that every current commit already achieves them.

## Principles

- Correctness outranks speed.
- Idle applications are event-driven.
- Work scales with visible/damaged content, not total logical history.
- Static subtrees do not rebuild, relayout, or repaint during unrelated streaming/animation.
- Benchmarks report distributions, not only averages.
- Noise-controlled regressions fail CI.

## Required metrics

Per frame:

```text
frameTotal
inputToFrameLatency
buildTime
reconciliationTime
layoutTime
paintTime
compositionTime
damageTime
diffEncodeTime
presentTime

dirtyElements
rebuiltElements
laidOutRenderObjects
paintedRenderObjects
compositedLayers
damageRegions
paintedCells
comparedCells
writtenCells
ansiRuns
outputBytes
allocations
```

Process-level: `idleCpu`, `activeCpu`, `rssBytes`, `heapBytes`, `gcTime`, `droppedFrames`, `eventQueueDepth`.

Timing metrics report p50, p95, p99, max, and sample count.

## Reference workloads

### A. Idle dashboard

- 120×40 viewport;
- at least 1,000 widgets/elements;
- no timers/animations;
- 60 seconds.

Contract: zero frames/writes after stabilization, no continuously active renderer timer, idle CPU target below 0.5% on the reference Linux runner with platform baselines recorded separately.

### B. Single-cell update

- 200×60 viewport;
- one cell changes per frame;
- 10,000 frames;
- no geometry changes.

Contract: unrelated subtrees do not rebuild, no layout after warm-up, one dirty boundary maximum, compared/written cells remain independent of screen area while precise damage exists, and no per-frame viewport-sized cell allocation.

### C. Streaming chat

- 10,000 logical messages;
- 60 visible rows;
- one active streaming Markdown message;
- 100 token deltas/second batched to frame cadence;
- fixed sidebar/composer/status.

Contract: old offscreen messages do not participate in active render/layout, no full-tree layout per token, one coalesced state/build update per frame rather than per token, p95 input-to-screen below 33 ms for the 30 FPS profile, zero dropped input, output bytes proportional to changed visible lines.

This depends on virtualization/incremental text at widget/application level; renderer metrics expose violations.

### D. Pet/logo animation

- animated region 30×15 cells;
- static surrounding chat/dashboard;
- 30 FPS for 30 seconds.

Contract: static repaint counts remain unchanged, paint/comparison stays near animated region, p95 frame below 33 ms on reference profile, and no full-screen writes.

### E. Huge log scroll

- 100,000 logical rows;
- 160×50 viewport;
- continuous one-row scroll;
- hardware-scroll enabled and disabled variants.

Contract: memory does not scale with retained rendered history, work scales with viewport/cache extent, hardware scroll is used only when safe/cheaper, and fallback is visually identical.

### F. Resize storm

Alternate representative sizes for 500 resizes with Unicode, images, selection, and nested clips. Contract: no crash/invalid wide pair, bounded memory after stabilization, correct full baseline after every resize, recoverable terminal after interruption.

### G. Unicode stress

Random grapheme strings containing combining marks, CJK, ZWJ, flags/modifiers, ambiguous-width characters, and wide/narrow replacement. Logical reference buffer and emulator state must match exactly.

### H. Layer cache

- 200×60 viewport;
- multiple static boundaries;
- one small dirty boundary;
- 10,000 frames.

Contract: clean descendants gain zero paint calls, cache hits measured, and composition allocates no memory proportional to layer area in steady state.

## Frame budgets

| Profile | Target FPS | Frame budget |
| --- | ---: | ---: |
| Low-power/remote | 15 | 66.7 ms |
| Default interactive | 30 | 33.3 ms |
| High-refresh small-region | 60 | 16.7 ms |

Cinder should prioritize 30 FPS. 60 FPS is not a promise for full-screen terminal animation. Reference workloads SHOULD keep p95 below selected budget and p99 below twice the budget.

## Latency

Input-to-screen starts when a complete logical event is decoded and ends when presentation returns. Streaming latency starts when a delta reaches the UI isolate. Queueing, rate limiting, rendering, and backend presentation are included.

## Memory/allocation

- reuse front/back buffers until resize;
- reuse stable cell storage;
- reuse/budget layer buffers;
- no full viewport object allocation per frame;
- reuse output-builder capacity where safe;
- explicit image/text cache budgets;
- report warm and steady-state allocations.

Leak tests repeat mount/unmount, resize, image placement, and route transitions then inspect post-GC retained growth.

## Output contract

Measure actual encoded backend bytes: bytes/frame, cursor moves, style/link transitions, full redraw count, sparse/row decisions, and image bytes separately. Lower CPU with greatly increased output is not automatically an improvement.

## CI methodology

Pin Dart/runtime mode, use noise-controlled runners where possible, warm up, run multiple samples, store raw JSON artifacts, compare median+p95, and do not fail on one noisy sample.

Suggested gates after baseline stabilization:

```text
p50 frame time       > 10% regression → fail
p95 frame time       > 15% regression → fail
output bytes         > 15% regression → fail
steady allocations   > 10% regression → fail
idle frames/writes   > 0               → fail
correctness mismatch                  → fail
```

Intentional regression requires evidence and changelog entry.

## Benchmark output schema

```json
{
  "benchmark": "streaming_chat",
  "commit": "...",
  "dart": "...",
  "os": "...",
  "terminalBackend": "...",
  "viewport": {"width": 160, "height": 50},
  "samples": 10000,
  "timingsUs": {"frameP50": 0, "frameP95": 0, "frameP99": 0},
  "cells": {"painted": 0, "compared": 0, "written": 0},
  "outputBytes": 0,
  "allocations": 0
}
```

## Public claims

Every published claim includes exact commit/tag, benchmark path, hardware/runner, OS/Dart, terminal/backend, viewport/workload, warm-up/sample count, and raw artifact. “Cinder is faster than X” is invalid without equivalent workloads.

## Current implementation status

Cinder already exposes frame/build/layout/paint rates and diff stats including compared cells, ANSI runs, written cells, and output code units; renderer and cached-layer microbenchmarks exist.

Required 1.0 work: byte-accurate output metrics, distributions/input latency, composition/damage timing, full workload suite, stored JSON baselines, CI regression gates, allocation/memory tracking, and explicit damage metrics.
