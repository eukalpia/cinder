# Renderer V2 architecture

> This file is an implementation snapshot. The normative renderer contract is
> [`renderer.md`](../renderer.md) and the documents in [`doc/rendering/`](rendering/overview.md).
> When this implementation note conflicts with the normative contract, the implementation
> is incomplete and must be migrated.

Renderer V2 is Cinder's terminal-cell rendering pipeline.

## Frame storage

- flat mutable cell arrays;
- reusable front/back buffers;
- per-row dirty spans;
- stable cell identities and cached grapheme widths;
- image overlay metadata kept alongside placeholder cells.

## Diff and output

- compare only the union of dirty row spans;
- merge cheap unchanged gaps into one cursor-positioned run;
- batch ANSI style transitions;
- preserve wide-grapheme continuation and removal semantics;
- wrap frames in synchronized output when supported.

## Cached layers

`RepaintBoundary` stops paint invalidation at the nearest boundary. Its subtree
is painted into a reusable local `Buffer`; unchanged frames blit the cached layer
without calling descendant paint methods. Dirty boundaries can be painted
directly into a synchronized back buffer without walking the root tree.

## Scroll regions

Full-width vertical list viewports can request DECSTBM scroll regions and CSI
`S`/`T` operations. Requests are rejected when the viewport is partial-width,
the delta is fractional or too large, or an active protocol image intersects the
region. Rejected requests use ordinary dirty-span rendering.

## Contracts

Dedicated tests cover cached paint counts, boundary invalidation, alternating
buffer synchronization, image metadata compositing, scroll mutation, escape
sequences, Unicode width, and differential output. Benchmarks cover single-cell
updates and repeated cached-panel composites at a 200x60 viewport.
