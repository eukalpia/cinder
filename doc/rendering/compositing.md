# Compositing and cached layers

Compositing combines painted cell layers and terminal-native overlays into the provisional frame.

## Why composition is separate

Paint answers what a subtree looks like locally. Composition decides placement, clip, z-order, cache reuse, image overlays, and old/new damage. Current Cinder blits cached buffers during paint; the 1.0 contract treats composition as a distinct logical stage and dirty domain.

## Layer model

```dart
final class TerminalLayer {
  Object owner;
  Buffer cells;
  RectI localBounds;
  OffsetI screenOffset;
  RectI clip;
  int generation;
  bool contentValid;
  List<ImagePlacement> images;
  DamageSet localDamage;
}
```

A mutable layer buffer is owned by one boundary. Composition borrows it read-only.

## Repaint boundaries

`RepaintBoundary` isolates descendant paint invalidation.

A cache hit requires unchanged dimensions, clean descendant content, compatible width/capability policy, valid image inputs, and no failed previous paint.

On a hit, descendant paint is skipped; composition may still damage when offset, clip, z-order, or overlay state changed.

On a miss: reuse/allocate local buffer, clear/synchronize safely, paint descendants, validate cells, retain provisional content, and promote only after safe composition/presentation. The current implementation clears/repaints then blits; stable behavior SHOULD retain last known-good content until replacement succeeds.

## `markNeedsCompositing`

```dart
void markNeedsCompositing();
```

Triggers include boundary offset, clip, z-order, opacity/tint/effect, image placement, cursor/selection overlay, insertion/removal. Propagation stops at nearest compositing boundary/root and queue entries are idempotent.

`markNeedsLayout` may imply composition. `markNeedsPaint` implies new layer content but not repaint of other layers.

## Composition order

For each layer in stable paint order:

1. transform local bounds/damage to screen;
2. intersect with parent/screen clip;
3. clear old placement when moved/removed;
4. blit cells;
5. merge image placements;
6. record global damage.

Later layers overwrite earlier cells. Protocol images follow an explicit policy relative to cell layers.

## Clips and wide cells

Layer blit must not mutate source, copy out of bounds, orphan a wide continuation at a clip edge, or carry invalid partial image placements. A clipped width-2 grapheme is omitted/replaced safely, never split.

## Layer-local damage

- unchanged content, moved placement: old ∪ new screen bounds; no descendant paint;
- changed content, fixed placement: transform local damage;
- unchanged/fixed: none;
- removal: old bounds + image cleanup.

## Effects

Opacity/tint resolves into destination colors. Reverse/selection/focus can be lightweight overlays preserving base cacheability. Shadows/glow are ordinary cells and expand paint/damage bounds.

## Images

Protocol placement metadata is part of a layer cache. Blit translates only complete valid placements. Partial clipping must re-encode/crop or fall back to Unicode, never advertise an out-of-clip placement.

## Cache eviction

Release buffers on dispose, incompatible size/capability change, memory-budget pressure, corruption, or low-memory policy. Eviction dirties the boundary but does not alter the physical front buffer. A future global budget SHOULD use least-recently-composited eviction with visible layers favored.

## Metrics

```text
layerCount
compositedLayers
dirtyLayers
layerCacheHits
layerCacheMisses
layerBytes
blittedCells
compositingDamageCells
```

Per-boundary debug data includes paint count, hits, last offset, layer size, generation, and last damage.

## Exception behavior

Composition errors preserve front buffer and last known-good cache, invalidate provisional affected content, schedule full/root repaint, and abort presentation when correctness is uncertain.

## Current implementation status

Implemented: `RepaintBoundary`, local reusable `Buffer`, boundary invalidation, cache-hit blits, partial topmost-boundary paint, and image metadata translation.

Specified gaps: `markNeedsCompositing`, explicit layer records/tree, local multi-region damage, transactional cache promotion, global memory budget, and effect-layer APIs.
