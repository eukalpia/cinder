# Layout and paint

Status: **normative**.

Layout computes geometry. Paint converts that geometry and visual configuration into
layer-local cell operations. Neither stage may perform terminal I/O.

## Layout contract

A render object receives immutable constraints from its parent and MUST choose a finite size
inside those constraints. It then lays out children, writes parent data, and records its own
paint bounds.

`performLayout` MUST:

- set `size` exactly once on every successful invocation;
- pass finite constraints to children unless the child API explicitly supports unbounded
  constraints;
- write child offsets before returning;
- avoid application state mutation;
- avoid terminal capability queries and I/O;
- be deterministic for equal configuration, child state, and constraints.

A parent that uses a child's size MUST declare that dependency. This determines the nearest
relayout boundary and the direction of dirty propagation.

## Layout skipping

A render object skips `performLayout` when all are true:

- it is not layout-dirty;
- incoming constraints are value-equal to the previous constraints;
- no intrinsic/baseline dependency used by the parent changed;
- no child-list or parent-data revision changed.

Identity comparison of constraints is insufficient. Cinder's current value-equality skip is
part of the public performance contract.

Skipping layout MUST preserve the previous size, child parent data, paint bounds, and hit-test
geometry.

## Layout passes

The pipeline lays out shallower relayout boundaries before deeper ones. One normal pass and
one stabilization pass are allowed per frame. A render object MAY be invoked in both only if
new constraints or a legitimate layout callback changed its inputs.

A third invocation for the same frame is a cycle. Debug mode throws a structured
`LayoutCycleError`; release mode defers remaining work to the next frame and forces paint
damage for the affected bounds.

## Layout exceptions

On exception, the framework reports the render-object type, constraints, frame ID, parent
chain, and stack trace. It assigns a bounded fallback size, marks the object as having a
layout error, and damages its previous and fallback bounds.

Children that were not successfully positioned MUST NOT be painted outside the fallback
clip. The rest of the tree continues when containment is possible.

## Paint contract

Paint receives a `TerminalCanvas`, a local-to-surface offset, and an effective clip. It emits
logical operations into the current layer surface.

Paint MUST:

- honor the clip;
- use grapheme-aware text APIs;
- preserve wide-cell atomicity;
- report the smallest conservative local damage bounds;
- paint children in deterministic order;
- call the superclass contract when required;
- leave application state unchanged;
- never retain the canvas or its buffer;
- never call backend write/flush methods.

Paint MAY allocate short-lived objects, but hot primitives SHOULD write directly into reusable
cells or display-list storage.

## Paint bounds

Every render object has local paint bounds. They default to its layout bounds but MAY extend
outside them for shadows, overflow, decorations, or protocol images. An object painting
outside layout bounds MUST declare the larger paint bounds so damage and clipping remain
correct.

When bounds change, both old and new root-space bounds are damaged.

## Repaint boundaries

A repaint boundary owns a reusable local surface. Paint invalidation stops at it. A clean
boundary MUST composite its cached surface without invoking descendant paint methods.

A boundary cache key includes at least:

- pixel/cell size;
- terminal width profile;
- effective clip relevant to the local surface;
- child paint revision;
- image protocol/capability revision;
- theme or inherited visual revision used by the subtree.

A changed global offset alone does not require repaint; it requires composition damage.

Each repaint boundary is painted at most once per frame. Repeated descendant invalidations
coalesce into one local damage set.

## Partial boundary paint

The required next-level implementation supports partial painting inside a cached boundary.
A boundary MAY retain its surface and repaint only local damage regions when:

- all paint operations are clipped correctly;
- removed content is explicitly cleared;
- wide glyph and image regions are expanded atomically;
- layer-local row hashes are updated;
- the cost model says partial paint is cheaper than clearing/repainting the full layer.

Otherwise it clears and repaints the complete boundary surface.

## Paint exceptions

A paint exception is contained to the current render object or repaint boundary. The renderer
reports the object, clip, offset, layer ID, and frame ID, then paints a bounded error surface.

If even error painting fails, the affected region is cleared and marked damaged. Paint
exceptions MUST NOT directly abort the terminal write unless they corrupt layer ownership or
buffer invariants.

## Hit testing consistency

Hit testing uses the last successfully committed layout geometry, not half-computed geometry
from an in-progress frame. A frame commits new hit-test geometry together with the visual
frame. This avoids pointer dispatch against content the user cannot yet see.

## Custom render-object obligations

Custom render objects must choose invalidation accurately:

- text/style/color change without geometry change: `markNeedsPaint`;
- text metrics, width, padding, flex, child list, parent data: `markNeedsLayout`;
- transform, opacity, clip, z-order, cached layer placement: `markNeedsCompositing`;
- widget/config dependency: element-side `markNeedsBuild`.

See [custom-render-objects.md](custom-render-objects.md) for the complete checklist.
