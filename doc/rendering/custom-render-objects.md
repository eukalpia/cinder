# Custom render objects

Status: **normative** public extension contract.

Custom render objects are allowed to participate in Cinder's optimized pipeline only when
they preserve the invariants in this section.

## Minimal shape

A custom render object normally implements:

- property setters with precise invalidation;
- `performLayout`;
- `paint`;
- child adoption/parent data when applicable;
- `hitTestSelf` and/or `hitTestChildren`;
- paint bounds when output exceeds layout bounds;
- attach/detach/dispose for owned resources.

## Property setter rules

Every mutable render property uses compare-then-mark semantics:

```dart
set color(Color value) {
  if (_color == value) return;
  _color = value;
  markNeedsPaint();
}
```

Choose the mark by effect:

| Change | Required mark |
|---|---|
| widget dependency/configuration | element `markNeedsBuild` |
| constraints, size, child position, text wrapping, intrinsic metrics | `markNeedsLayout` |
| colors, glyphs with unchanged metrics, cursor/selection decoration | `markNeedsPaint` |
| transform, opacity, clip, z-order, layer placement/topology | `markNeedsCompositing` |

When unsure, use the broader mark and add a benchmark/test before narrowing it.

## Layout checklist

`performLayout` must:

- consume current `constraints`;
- set finite `size`;
- lay out each active child with correct constraints;
- set every child's parent data/offset;
- avoid retaining stale child geometry after child removal;
- avoid state mutation or scheduling loops;
- declare larger paint bounds if drawing overflows layout bounds.

A parent depending on child size must pass `parentUsesSize: true` or the equivalent contract.

## Paint checklist

`paint` must:

- honor the canvas clip;
- paint only through grapheme/cell-safe APIs;
- never directly mutate raw continuation cells;
- call child `paintWithContext` in deterministic order;
- include old/new overflow bounds in damage when visual extent changes;
- avoid terminal writes and `flush`;
- avoid storing the canvas;
- keep protocol image commands in image metadata, not backend output.

## Unicode rules

Use extended grapheme clusters. Never iterate user-visible text by UTF-16 code unit.

Custom text painting must delegate width to the frame's terminal width profile. It must not
split wide graphemes at clips or row ends. Combining marks and emoji ZWJ sequences follow the
[cell contract](cell-buffer.md).

## Repaint boundaries and layers

Override or request repaint-boundary behaviour only when the subtree has meaningful reuse.
A boundary must not cache borrowed canvases, parent buffers, or terminal output bytes.

Composition-only properties should not invalidate the painted surface. Until
`markNeedsCompositing` is implemented, document conservative paint invalidation and add a
migration test.

## Damage reporting

A custom primitive should report the smallest conservative integer cell bounds. Damage must
expand for:

- old and new positions;
- complete wide graphemes;
- complete image ownership regions when required;
- shadows/overflow/decoration outside layout bounds.

Under-reporting is a correctness bug. Moderate over-reporting is correct but measured as a
performance issue.

## Exceptions

Throwing from layout or paint is contained by the framework, but custom objects should fail
with actionable errors before corrupting storage. Include invalid constraints, dimensions,
protocol, or grapheme data in error messages.

Dispose owned timers, controllers, native handles, image resources, and layer leases. A
detached object must not continue marking the old pipeline owner dirty.

## Required tests

Every custom render object should test:

1. initial layout/paint;
2. each property setter's exact invalidation;
3. unchanged-property no-op;
4. value-equal constraint layout skip;
5. resize and clipping;
6. child insert/remove/reorder if applicable;
7. hit testing;
8. wide, combining, emoji ZWJ, Arabic, Cyrillic, and CJK content when text is painted;
9. repaint-boundary cache behaviour if used;
10. exception containment;
11. no stdout write outside terminal diff;
12. full-reference versus optimized rendering equivalence.

## Debug assertions

Debug mode should assert:

- finite size after layout;
- child parent data type and offsets;
- no dangling wide continuation in touched rows;
- paint damage contains all touched cells;
- no backend writes during layout/paint;
- no more than one boundary paint per frame;
- disposed objects are not attached or dirty.

## Compatibility

Custom render objects written against this contract remain source-compatible when storage
moves from current `Cell`/row-span internals to canonical `TerminalCell`, multiple damage
regions, row hashes, and explicit compositing dirtiness, provided they use public canvas and
invalidation APIs rather than raw buffer mutation.
