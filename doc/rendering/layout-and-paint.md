# Layout and paint contract

Layout determines geometry. Paint converts geometry and visual state into logical terminal cells. They are separate phases with separate invalidation.

## Layout contract

Every render object receives `BoxConstraints` and produces a finite `Size`.

```dart
void layout(BoxConstraints constraints, {bool parentUsesSize = false});
void performLayout();
```

A render object may skip `performLayout` only when it is clean and constraints are value-equal to previous constraints.

### Constraint invariants

- `minWidth <= maxWidth` and `minHeight <= maxHeight`.
- Negative minimum dimensions are normalized or rejected.
- `performLayout` MUST set `size`.
- Resulting dimensions MUST be finite and satisfy constraints.
- A child MUST be laid out before its size is read.
- Parent-data offsets MUST be updated in the same successful layout pass.
- Terminal resize invalidates root constraints and dependent layout.

### Parent size dependencies

When `parentUsesSize` is true, a child geometry change can invalidate its parent. A relayout boundary may stop upward propagation only when parent geometry is independent of the changed child, parent constraints are unchanged, and debug validation confirms no ancestor geometry changed.

### Layout ordering and pass limit

Dirty nodes are processed so parents provide constraints before children lay out. If an allowed layout callback creates/dirties nodes, the queue is re-sorted.

Ordinary flow performs at most one successful `performLayout` per object per frame. Additional passes require a documented callback/intrinsic measurement, a convergence counter, a hard pass limit, and diagnostics naming loop participants. Recommended maximum: eight passes, with ordinary widgets expected to use one.

### Layout mutation rules

Allowed during `performLayout`:

- laying out children;
- updating this object's size;
- writing child parent data;
- invoking a framework-provided synchronous layout callback;
- updating internal layout caches.

Forbidden:

- application state mutation;
- terminal writes;
- async work;
- focus changes;
- arbitrary child-list mutation outside the documented callback;
- reading stale child size without laying it out.

### Layout cache

A render object may cache previous constraints, computed size, line wrapping, child extents, intrinsic measurements, baselines, and parent-data offsets. Every cache documents invalidation inputs and must never make a dirty object skip required layout.

## Paint contract

```dart
void paint(TerminalCanvas canvas, Offset offset);
```

Paint receives valid geometry and writes only through the supplied canvas.

### Paint invariants

- Paint MUST respect the canvas clip.
- Paint MUST be deterministic for equal state and inputs.
- Paint MUST not mutate application state or tree structure.
- Paint MUST not emit ANSI or call the backend.
- Children are painted in stable render-child order.
- Later writes replace earlier cell content unless an explicit blend/tint operation is used.
- A render object clears paint-dirty state only through successful paint/error fallback.
- Paint operations preserve wide-cell invariants.

### Paint bounds

Every render object SHOULD provide conservative local paint bounds. Default bounds are `Rect.fromLTWH(0, 0, size.width, size.height)`. Objects painting outside layout bounds must override paint bounds and use a defined clip/overflow contract. Damage uses paint bounds, not only layout size.

### Child painting

A parent establishes child clip, reads parent-data offset, calls `child.paintWithContext`, never paints detached children, and never reuses stale offsets after layout changes. A repaint boundary may paint its child into a local buffer and later composite it.

### Paint frequency

- Full paint: one root walk.
- Partial paint: one paint per topmost dirty repaint boundary.
- A descendant inside one dirty boundary MUST not paint twice in one frame.
- A clean cached subtree is not painted.
- Paint invalidation raised during paint is deferred to the next frame.

## `TerminalCanvas`

`TerminalCanvas` is the only supported paint target. It provides clipped text/grapheme drawing, cell fills/borders, tint/blend, nested clips, cached-buffer blits, and image placement metadata.

Canvas operations MUST clip in integer cell space, normalize overwritten wide cells, mark conservative damage, avoid out-of-bounds mutation, and preserve image-overlay consistency. Custom render objects must not access binding front/back buffers directly.

## Transparency and blending

Terminals do not expose a retained alpha framebuffer. Alpha is resolved during paint against logical destination colors. Foreground/background alpha blend deterministically, unspecified components preserve existing components only where explicitly documented, and moving translucent content damages old and new bounds.

## Selection and debug overlays

Selection, focus indicators, repaint-rainbow, and diagnostics are paint/composition overlays. They must not permanently mutate underlying document cells. Overlay changes dirty only affected bounds.

## Error handling

### Layout error

When `performLayout` throws, report render identity/constraints, assign a finite constrained fallback size, mark layout error state, permit ancestors to complete where possible, paint an error box, and do not promote failed layout caches.

### Paint error

When paint throws, report bounds/stack, paint a minimal guarded error box, leave the provisional area blank/damaged if fallback fails, and do not replace the last known-good cached layer.

### Root failure

If root layout/paint cannot produce a safe frame, presentation is aborted and the previous front buffer remains authoritative.

## Current implementation status

Implemented: value-equal constraint skipping, finite fallback size, render error box, paint exception handling, repaint-boundary buffers, clipped canvas, and partial topmost-boundary painting.

Specified gaps: explicit paint-bounds API, layout convergence guard, damage emitted directly by all canvas operations, separate compositing dirty flag, and transactional last-known-good layer promotion.
