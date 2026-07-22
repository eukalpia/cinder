# Compositing

Status: **normative**.

Compositing combines painted layer surfaces into one resolved terminal-cell framebuffer.
It is separate from paint so unchanged painted content can move, clip, fade, reorder, or be
reused without repainting descendants.

## Layer model

A logical layer contains:

```dart
final class TerminalLayer {
  LayerId id;
  Buffer surface;
  Offset offset;
  Rect clip;
  double opacity;
  BlendMode blendMode;
  int paintRevision;
  int compositionRevision;
  DamageSet localDamage;
  List<TerminalLayer> children;
}
```

The exact storage MAY differ. The observable requirements do not.

## Ownership

The compositing owner owns the layer graph. Repaint boundaries own or lease their local
surfaces. A layer surface remains valid until its paint revision changes, terminal-size/width
profile invalidates it, or cache eviction disposes it.

A render object MUST NOT directly dispose a surface still referenced by a committed layer.
Eviction occurs between frames or through reference-counted ownership.

## `markNeedsCompositing`

Composition dirtiness is required for changes to:

- layer offset or transform;
- clip;
- opacity or blend mode;
- z-order;
- child-layer topology;
- image overlay placement/revision;
- selection or hyperlink metadata applied during composition;
- repaint-boundary cache identity.

A composition-only change MUST reuse the painted surface when valid. Falling back to repaint
is allowed but is a measurable performance defect.

## Composition order

Layers compose back-to-front in deterministic tree order. For each cell:

1. transform and outward-round local coordinates;
2. intersect with the effective clip;
3. clear invalidated old wide/image ownership;
4. resolve background channel;
5. resolve text occupancy and foreground/attributes;
6. apply selection decoration;
7. install hyperlink/semantics metadata;
8. register image placeholder ownership.

Text clusters are atomic. A top layer cannot reveal half of a lower wide grapheme.

## Transparency

Layer surfaces may contain transparent foreground/background channels. Composition resolves
alpha against lower layers. The root result is opaque or uses explicit terminal-default
sentinels.

Opacity applies to colors, not to grapheme identity. A text cell with effective opacity zero
contributes no text occupancy. Terminals do not support arbitrary alpha, so all blending is
completed before diff.

## Clips and transforms

Cinder's terminal output grid is discrete. Transforms that do not resolve to integral cell
placement MUST outward-round damage and use the documented snapping policy for content.
Arbitrary rotation and scale MAY be unsupported by a terminal layer; unsupported transforms
must fail explicitly rather than silently corrupt cell ownership.

Clips are inherited and intersected. Moving a clipped layer damages both its previous visible
bounds and current visible bounds.

## Layer-local damage

Paint writes local damage. Composition transforms only those local regions plus old/new
placement bounds into parent coordinates. A clean layer with no placement change contributes
no new damage and MAY be skipped entirely.

Layer-local region count is capped at 16 by default. A layer exceeding the cap collapses to
local row spans or full-layer damage before parent transformation.

## Cache admission and eviction

A surface SHOULD be cached when reuse is likely to recover its memory and composition cost.
The cache policy considers:

- surface cell count;
- paint cost history;
- reuse count;
- image payload size;
- current global layer memory;
- terminal dimensions;
- frame pressure.

Cache memory has a configurable hard budget. Default guidance is the lesser of:

- four complete terminal frames; or
- 32 MiB of cell surfaces and metadata.

The root front/back buffers are excluded from the layer-cache budget. Exceeding the hard
budget triggers least-recently-used eviction between frames. A surface used by the current
frame cannot be evicted.

## Composition exceptions

Composition is transactional. If it throws:

- the back buffer is discarded or marked invalid;
- the previous front buffer remains committed;
- no terminal diff or visual write occurs;
- all involved root bounds are forced dirty for the next frame;
- the layer graph is rebuilt or fully recomposited next frame;
- diagnostics include layer ID, revisions, transforms, clips, and frame ID.

## Metrics

The renderer publishes:

- composed layer count;
- skipped clean layer count;
- cache hits/misses/evictions;
- painted versus composited cell counts;
- local and root damage regions;
- bytes owned by root buffers and layer caches;
- full-layer repaint fallbacks and reasons.
