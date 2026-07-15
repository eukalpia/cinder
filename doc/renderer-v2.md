# Renderer V2 implementation notes

Renderer V2 is Cinder's current reusable terminal-cell renderer implementation.

The normative Cinder 1.0 rendering contract now lives in:

- [`renderer.md`](renderer.md)
- [`rendering/overview.md`](rendering/overview.md)
- [`rendering/frame-pipeline.md`](rendering/frame-pipeline.md)
- [`rendering/cell-buffer.md`](rendering/cell-buffer.md)
- [`rendering/damage-tracking.md`](rendering/damage-tracking.md)
- [`rendering/layout-and-paint.md`](rendering/layout-and-paint.md)
- [`rendering/compositing.md`](rendering/compositing.md)
- [`rendering/terminal-diff.md`](rendering/terminal-diff.md)
- [`rendering/images.md`](rendering/images.md)
- [`rendering/scroll-regions.md`](rendering/scroll-regions.md)
- [`rendering/performance-contract.md`](rendering/performance-contract.md)
- [`rendering/custom-render-objects.md`](rendering/custom-render-objects.md)

This file is implementation-oriented. When it differs from the normative specification, the difference is a tracked implementation gap for stable 1.0.

## Current frame storage

- flat mutable cell arrays;
- reusable front/back buffers;
- one dirty span per row;
- stable cell identities and cached grapheme widths;
- `\u200B` continuation markers for width-2 graphemes;
- image overlay metadata alongside placeholder cells.

The 1.0 specification formalizes `TerminalCell`, `CellKind`, wide-cell normalization, hyperlink/selection metadata, multiple spans, and row hashes.

## Current diff/output

- compare union of current/previous dirty row spans;
- merge cheap unchanged gaps into cursor-positioned runs;
- batch ANSI style transitions;
- preserve wide continuation/removal semantics;
- wrap frames in synchronized output when supported;
- flush once after frame operations.

Stable 1.0 additionally requires an explicit frame-payload builder and one backend `present` transaction.

## Current cached layers

`RepaintBoundary` stops invalidation at the nearest boundary. Its subtree paints into a reusable local `Buffer`; clean frames blit cached content without descendant paint. Dirty topmost boundaries can paint into a synchronized back buffer without a root walk.

Stable 1.0 adds explicit compositing dirtiness, layer-local damage, transactional promotion, and cache memory policy.

## Current scroll regions

Full-width vertical viewports may request DECSTBM plus CSI `S`/`T`. Partial-width, invalid delta, or intersecting protocol-image requests fall back to ordinary damage diff.

Stable 1.0 adds deterministic multi-request policy, byte-cost gating, failure transaction rules, and rejection metrics.

## Current validation

Tests cover cached paints, invalidation, alternating synchronization, image metadata composition, scroll mutation, escapes, Unicode width, and differential output. Benchmarks cover single-cell update and repeated cached-panel composition at 200×60.

The release-gate workload matrix is in [`rendering/performance-contract.md`](rendering/performance-contract.md).
