# Performance contract

Status: **normative**.

Performance is an API property. Correct output that performs unbounded work for a local
change violates this contract.

## Required asymptotic behaviour

Let:

- `E` be mounted elements;
- `R` be mounted render objects;
- `W × H` be terminal cells;
- `D` be damaged cells after normalization;
- `L` be affected layers;
- `V` be visible children in a lazy viewport.

Required behaviour:

| Scenario | Required upper bound |
|---|---|
| idle frame | no frame scheduled; O(1) bookkeeping |
| one element state change | O(dirty build subtree), not O(E) |
| visual-only leaf change | O(tree depth) invalidation + affected boundary paint |
| unchanged constraints | O(1) layout skip per visited boundary |
| one-cell root damage | O(damage regions + dirty rows + D), not O(W × H) |
| clean cached boundary | O(composited visible layer cells) or layer-damage cost, no descendant paint |
| full terminal resize | O(W × H + R affected by constraints) |
| lazy variable-height viewport scroll | O(log N + V + cache extent), not O(N) |
| terminal diff | O(candidate rows + compared damaged spans), full-frame only on explicit fallback |

## Idle contract

When no event, timer, animation, dirty node, cursor change, or out-of-band command is pending:

- no build/layout/paint/composition/diff runs;
- no visual stdout write occurs;
- no periodic full-buffer clear occurs;
- renderer CPU approaches the backend event-loop baseline.

Debug overlays may schedule frames only while explicitly enabled.

## Stage execution budgets

Per frame:

- each dirty element rebuilds at most once per build epoch;
- layout has at most two global stabilization passes;
- each repaint boundary paints at most once;
- each layer composes at most once;
- damage normalization runs once;
- terminal diff runs once;
- visual backend write count is 0 or 1.

Violations are counted and surfaced in debug/profile mode.

## Damage budgets

Defaults:

- maximum 16 local damage regions per layer;
- maximum 64 root damage regions;
- row hashes for all committed rows;
- full-frame fallback only when estimated regional/row work is at least 80% of full-frame
  cost, region caps collapse to full coverage, terminal desynchronization occurs, or resize
  invalidates storage.

The 80% threshold is configurable through the terminal cost profile and must be benchmarked.

## Memory contract

For a stable terminal size, Cinder owns exactly two root framebuffer cell arrays plus bounded
metadata and cache structures. It MUST NOT allocate a new `TerminalCell` for every screen
position every frame.

Root memory is O(W × H). Layer-cache memory is bounded by a configurable hard limit. Default
cache guidance is the lesser of four full-frame-equivalent surfaces or 32 MiB, excluding root
front/back buffers.

Damage structures are bounded. Per-frame temporary allocation SHOULD be proportional to
changed runs/layers, not screen size.

## Unicode cost

Grapheme segmentation and width calculation SHOULD occur once per changed text run. Widths
MAY be cached by immutable grapheme and terminal-width-profile revision. Cache invalidation is
mandatory when the profile changes.

Diff and composition MUST use cached canonical width and MUST NOT repeatedly segment the same
unchanged text per cell.

## Required metrics

`RendererFrameStats` must expose at least:

```dart
final class RendererFrameStats {
  int frameId;
  Duration buildTime;
  Duration reconciliationTime;
  Duration layoutTime;
  Duration paintTime;
  Duration compositionTime;
  Duration damageTime;
  Duration diffTime;
  Duration outputTime;

  int builtElements;
  int laidOutRenderObjects;
  int paintedRenderObjects;
  int paintedCells;
  int compositedLayers;
  int compositedCells;
  int damageRegionCount;
  int dirtyRowCount;
  int damagedCellUpperBound;
  int rowHashChecks;
  int rowHashHits;
  int comparedCells;
  int emittedCells;
  int cursorMoves;
  int styleTransitions;
  int outputBytes;
  int stdoutWrites;

  int layerCacheHits;
  int layerCacheMisses;
  int layerCacheEvictions;
  int acceptedScrollRequests;
  int rejectedScrollRequests;
  bool fullFrameFallback;
  String? fullFrameFallbackReason;
  bool committed;
}
```

Names may evolve, but all information must remain available through profiling APIs.

## Painted cells per frame

`paintedCells` counts cell writes performed by paint into layer/root surfaces, including
clears. It is distinct from:

- `compositedCells`: cells read/written during layer composition;
- `damagedCellUpperBound`: conservative spatial candidate count;
- `comparedCells`: front/back cells actually compared;
- `emittedCells`: terminal columns represented by output graphemes/clears.

The debug overlay must show current, rolling average, p50, p95, and maximum painted cells per
frame.

## Benchmark gates

CI benchmarks must cover:

1. idle scheduling;
2. one-cell text/style update on 80×24, 200×60, and 400×120 frames;
3. full repaint;
4. cached repaint-boundary hit and miss;
5. 1, 8, 32, 64, and 128 damage regions;
6. sparse changes across many rows;
7. wide glyph replacement and clearing;
8. emoji ZWJ and combining-mark text;
9. image placement/update/delete;
10. accepted and rejected scroll-region paths;
11. 100k variable-height anchored/lazy history scroll.

A pull request that changes renderer hot paths must publish before/after metrics. CI should
fail on statistically stable regressions above configured budgets, not on a single noisy run.

## Correctness before optimization

Every optimization needs a reference path or emulator assertion. The optimized result must
match a forced full layout/paint/composition/diff result for randomized trees, Unicode text,
clips, layers, images, and scroll operations.

A cache or hash may cause extra work on uncertainty. It must never suppress required output.

## Production defaults

Production builds enable reusable buffers, dirty tracking, row hashes, bounded damage
coalescing, layer caches, synchronized output, and safe scroll acceleration. Expensive
verification and per-cell tracing remain debug/profile options.
