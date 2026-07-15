# Damage tracking

Damage tracking identifies physical terminal cells that may differ after a frame. False-positive damage is allowed; false-negative damage is forbidden.

## Dirty domains

### Build

`Element.markNeedsBuild()` marks one active element, enqueues it once in `BuildOwner`, schedules a frame, and does not directly dirty ancestors/descendants.

### Layout

`RenderObject.markNeedsLayout()` marks geometry stale, implies paint, propagates according to parent-size dependency, schedules visual work, and is idempotent. Current Cinder conservatively propagates to root; future relayout boundaries may stop only when parent geometry is independent.

### Paint

`RenderObject.markNeedsPaint()` marks visible cells stale, propagates to nearest repaint boundary/root, enqueues once, and does not require layout when geometry remains valid.

### Compositing

`RenderObject.markNeedsCompositing()` marks layer placement, clip/effect, z-order, cursor, or image metadata stale; propagates to nearest compositing boundary/root; preserves valid descendant pixels when possible. This is normative and not yet implemented.

## Propagation table

| Source change | Build | Layout | Paint | Compose |
| --- | ---: | ---: | ---: | ---: |
| Text/color in same geometry | Maybe | No | Yes | No |
| Widget type/key/children | Yes | Often | Yes | Maybe |
| Child add/remove/reorder | Reconcile | Yes | Yes | Maybe |
| Resize/constraints | No | Yes | Yes | Yes |
| Padding/flex/position | Maybe | Yes | Yes | Maybe |
| Boundary offset only | No | No | No | Yes |
| Clip/opacity/effect | Maybe | Maybe | Maybe | Yes |
| Image placement/protocol | Maybe | Maybe | Yes | Yes |
| Selection highlight | Maybe | No | Yes | No |
| Scroll offset | Maybe | Layout/compose by design | Yes/exposed rows | Yes |

## Render bounds

Paintable render objects SHOULD expose conservative terminal-space paint bounds. Boundaries record previous/current bounds, local dirty bounds, offset, clip, and generation. Moving/shrinking damages old ∪ new bounds.

## Damage representation

```dart
final class DamageSet {
  List<RectI> regions;
  Map<int, List<SpanI>> rowSpans;
  bool fullScreen;
}
```

Requirements:

- integer clipped half-open coordinates;
- empty regions discarded;
- paint, composition, image cleanup, cursor, and scroll exposure combined before diff;
- wide-cell writes expand to both halves.

## Multiple rectangles and caps

Disjoint regions MUST be preserved while beneficial. Suggested defaults:

```text
maxDamageRegions = 64
maxSpansPerRow   = 16
```

When exceeded: merge overlap, bridge cheap gaps, coarsen to row spans, bounding rectangle, then full-screen when cheaper. Policy decisions are recorded in metrics.

## Region merging

A deterministic estimate compares separate area/metadata cost with bounding-rectangle cost. Merge overlap/touching regions and separated regions when scanning the gap is cheaper than tracking two regions. Benchmark-derived bias must remain stable for a release.

## Row spans

Project rectangles into rows; sort and merge overlapping/touching spans; bridge small gaps only under the terminal-run cost model; expand around wide pairs; include current+previous spans.

Current implementation has one `[dirtyStart, dirtyEnd]` span per row. The 1.0 target supports multiple spans.

## Row hashes

Front/back rows SHOULD maintain fast value hashes to reject unchanged damaged rows, validate layer composites, and detect untracked mutations in debug mode.

Hashes include grapheme, colors, attributes, width/kind, hyperlink, and placeholder semantics; invalidate on every write. Debug/fuzz modes periodically verify equality by values.

## Layer-local damage

A repaint boundary tracks damage locally. Composition transforms/clips it.

```text
content unchanged + moved → damage old ∪ new, skip descendant paint
content changed + fixed   → transform local damage
unchanged + fixed          → no damage
```

Removal damages old bounds and schedules image cleanup.

## Hardware-scroll damage

A successful hardware scroll mutates the physical baseline model identically. Damage includes exposed rows and overlays that cannot move. Rejected requests use ordinary viewport damage.

## Cost model

For a row compare sparse cursor/style/run bytes with whole-row bytes. Choose row rewrite when cheaper or fragmentation exceeds cap. The model is deterministic and benchmark-visible.

Current implementation bridges unchanged gaps up to four cells; the stable model uses byte cost while retaining a fixed fast path.

## Full-screen fallback

Required for first frame, resize, unknown baseline, uncertain partial write, invariant failure, or explicit full repaint. It may also be chosen when estimated diff cost exceeds full redraw.

## Metrics

```text
damageRegions
damagedRows
damagedCellsUpperBound
paintedCells
comparedCells
writtenCells
ansiRuns
outputBytes
fullRedraw
rowRewrites
sparseRuns
layerCacheHits
layerCacheMisses
```

Debug assertions verify every changed cell lies in damage, continuation pairs are valid, queues have no duplicates, and front-buffer cells do not change before successful presentation.

## Exception behavior

If damage calculation fails or detects invalid geometry, abandon the provisional set and retry with full-screen damage. If safe full redraw cannot be encoded, do not present and preserve the previous baseline.
