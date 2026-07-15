# Damage tracking

Status: **normative**.

Damage tracking answers two different questions:

1. which framework objects must rebuild, relayout, repaint, or recompose;
2. which terminal cells may differ from the committed front frame.

The first is tree dirtiness. The second is spatial damage. They are related but not
interchangeable.

## Dirty APIs

### `markNeedsBuild`

`markNeedsBuild` marks one mounted `Element` for the next build epoch and requests a frame.

Propagation rules:

- it does not recursively dirty ancestors or descendants;
- dependency invalidation MAY mark multiple dependent elements;
- a rebuilt parent may reconcile, update, replace, or remove descendants;
- render-object mutations produced by reconciliation must separately mark layout, paint,
  or composition dirty.

Repeated calls in the same build epoch are idempotent. An element dirtied while it is being
rebuilt is scheduled for the next epoch, not rebuilt reentrantly.

### `markNeedsLayout`

`markNeedsLayout` marks geometry stale and MUST also imply paint damage.

Propagation rules:

- dirtiness propagates upward until the nearest relayout boundary whose parent does not
  depend on its size, or the root;
- descendants are not marked eagerly; the dirty parent decides which children receive new
  constraints;
- changing child order, parent data, intrinsic dimensions, text metrics, terminal width,
  or any size-affecting property requires layout dirtiness;
- the old painted bounds and new painted bounds are both spatially damaged.

The current Cinder implementation propagates to the root. Introducing explicit relayout
boundaries is compatible with this contract and required for large trees.

### `markNeedsPaint`

`markNeedsPaint` marks visual output stale without invalidating geometry.

Propagation rules:

- it propagates upward to the nearest repaint boundary or root;
- it MUST NOT dirty descendants;
- a dirty repaint boundary repaints its local surface once;
- ancestors above the boundary need composition damage only when the boundary's placement,
  opacity, clip, or blend result changes;
- repeated marks are idempotent but MUST still guarantee that a frame is scheduled.

### `markNeedsCompositing`

`markNeedsCompositing` marks layer topology or layer placement stale.

It is required when transform, opacity, clip, z-order, layer bounds, cached-surface identity,
image plane, or compositing metadata changes without requiring the child to repaint.

Propagation rules:

- it propagates upward to the nearest compositing boundary or root;
- it does not imply child layout;
- it MAY reuse unchanged painted layer surfaces;
- it damages both previous and current root-space layer bounds;
- repeated marks are idempotent.

Until Cinder exposes this flag in code, callers must conservatively use `markNeedsPaint`.
That is an implementation fallback, not the final API.

## Dirty-state relationship

```text
markNeedsBuild
    └─ reconciliation may cause layout / paint / composition

markNeedsLayout
    ├─ geometry dirty
    ├─ paint dirty
    └─ composition dirty when bounds or placement change

markNeedsPaint
    └─ local layer paint dirty

markNeedsCompositing
    └─ layer placement/topology dirty; paint cache may remain valid
```

A broader state dominates a narrower one for scheduling, but the renderer MUST preserve the
narrow information for metrics and cache decisions.

## Spatial damage representation

The canonical representation is a bounded set of half-open integer rectangles:

```dart
final class DamageRegion {
  int left;
  int top;
  int right;
  int bottom;
  DamageSource source;
  LayerId? layerId;
}
```

Every region MUST be clipped to its owning surface. Empty regions are discarded. Regions
are expanded to cover complete wide graphemes and image ownership rectangles where the
protocol requires atomic replacement.

A frame keeps:

- layer-local region sets;
- root-space region set;
- per-row candidate spans;
- per-row content hashes for front and back buffers.

## Region accumulation

A paint primitive adds the smallest integer cell rectangle that can contain its output.
Text damage includes every occupied column, not the UTF-16 length. Clearing or moving a
layer adds its previous bounds. Relayout adds the union of old and new paint bounds.

Damage from a child layer is transformed outward into parent coordinates during composition.
Clips intersect the new paint region but do not erase damage required to clear old content.

## Region merging

Before terminal diff, damage regions are normalized:

1. discard empty or fully clipped regions;
2. expand Unicode/image atomic regions;
3. merge intersecting regions;
4. merge edge-touching regions when the estimated extra comparison cost is cheaper than
   maintaining two regions;
5. convert the result to per-row spans;
6. cap region count.

The default hard cap is **64 root damage regions per frame** and **16 local regions per
layer**. Implementations MAY tune these constants with benchmark evidence.

When a cap is exceeded, regions MUST collapse deterministically in this order:

1. merge regions sharing rows into row spans;
2. merge the cheapest gaps according to the cost model;
3. collapse to dirty rows;
4. fall back to full-frame damage only when row coverage is no longer cheaper.

Unbounded region lists are forbidden.

## Row-level hashes

Every committed and composed row has a 64-bit or stronger content hash covering:

- canonical cell kind, grapheme, width, resolved colors, and attributes;
- hyperlink and selection result;
- image placeholder ownership and protocol-visible revision.

A matching hash permits the row to skip cell-by-cell comparison even when conservative
damage intersects it. Hash collisions MUST only cause extra output avoidance if confirmed by
cell comparison in debug/verification mode; production may rely on a strong non-cryptographic
hash when collision risk is documented and tested.

Hashes are recomputed only for rows whose composed content may have changed.

## Cost model

The renderer chooses among a region run, complete row, multiple rows, and full frame.
A reference cost model is:

```text
regionCost = cursorMoveCost
           + comparedCells
           + expectedStyleTransitions * styleTransitionCost
           + regionBookkeepingCost

rowCost    = rowCursorCost
           + rowWidth
           + expectedRowStyleTransitions * styleTransitionCost

fullCost   = terminalHeight * rowCost
```

A gap between two spans is merged when comparing/emitting the gap costs less than another
cursor move plus another style/hyperlink state setup. Constants are terminal-profile inputs,
not magic values in widgets.

The decision MUST be deterministic for identical frame state and profile.

## Scroll mutation damage

An accepted terminal scroll-region operation mutates the model of the committed front buffer
before ordinary diff. The newly exposed rows are damaged; shifted rows are updated in the
front model without being repainted. Rejected scroll requests add ordinary paint damage.

## Damage statistics

Each frame MUST publish at least:

- `damageRegionCount`;
- `layerDamageRegionCount`;
- `dirtyRowCount`;
- `damagedCellUpperBound`;
- `rowHashChecks` and `rowHashHits`;
- `wideGlyphDamageExpansions`;
- `imageDamageExpansions`;
- `fullFrameFallbackReason`;
- `paintedCells`;
- `compositedCells`;
- `comparedCells`;
- `emittedCells`.

The debug overlay MUST be able to show painted cells per frame and rolling percentiles.

## Failure handling

If region transformation or normalization throws, the frame is aborted and the next frame
is forced to full-frame damage. The previous front buffer remains committed. Debug mode MUST
report the source layer, original region, transformed region, and frame ID.
