# Cinder renderer specification

> Status: **normative P0 specification for the Cinder 1.0 renderer**
>
> This document defines observable renderer behavior. The files under
> [`doc/rendering/`](rendering/overview.md) expand each subsystem. When the current
> implementation differs from this specification, the difference is an implementation
> gap, not an alternative contract.

## Normative language

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are used as
RFC 2119-style requirements.

The specification distinguishes:

- **contract** — behavior implementations must provide before stable `1.0.0`;
- **current implementation** — behavior present in the development line;
- **planned** — specified behavior not yet implemented.

## Scope

The renderer owns the path from an input event or scheduled state mutation to one
atomically presented terminal frame. It does not own application business logic,
networking, persistence, or model inference.

The canonical frame pipeline is:

```text
Input / Event
      ↓
State mutation
      ↓
Build
      ↓
Element reconciliation
      ↓
Layout
      ↓
Paint
      ↓
Layer composition
      ↓
Damage calculation
      ↓
Terminal diff
      ↓
Single batched stdout write
```

A frame is a coalesced unit of visual work. Multiple input events, timers, stream
updates, and `setState` calls MAY be combined into one frame. A renderer MUST NOT
present a partially built frame.

## Global frame invariants

1. A frame MUST observe one logically consistent widget/render state.
2. Build, layout, paint, composition, damage calculation, and diff MUST execute in
   the documented order when they are required.
3. A clean stage MUST be skipped.
4. Dirty marking MUST be idempotent.
5. State mutation during a prohibited phase MUST be rejected in debug mode and
   deferred or reported in release mode.
6. The previous physical-terminal state MUST remain the comparison baseline until
   the new frame has been successfully presented.
7. A failed frame MUST NOT replace the previous front buffer.
8. Terminal state restoration MUST run even when build, layout, paint, diff, image
   output, or backend output throws.
9. All ANSI, image, cursor, synchronized-output, and IME-cursor commands belonging
   to one frame MUST be assembled into one frame payload and submitted as one
   backend presentation transaction.
10. A frame MUST NOT execute more than one terminal presentation.

## Stage contract matrix

| Stage | Runs when | Dirty sources | May be skipped when | Cached state | Memory owner | API guarantee | Maximum executions per frame | Exception behavior |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Input / event | Backend emits keyboard, mouse, paste, resize, signal, timer, or platform event | Backend event queue | No event is available | Parsed input buffer, terminal capabilities | `TerminalBinding` / backend | Events are decoded into complete logical events before dispatch | Unbounded events may be drained, but dispatch is finite and ordered | Malformed sequences are isolated; terminal cleanup remains armed |
| State mutation | Event handler, timer, listenable, stream, animation, or application callback changes state | `setState`, notifier updates, controller mutations | No mutation occurred | Application-owned state | Application objects, `State`, controllers | Mutations mark the minimum required downstream stage dirty | Multiple mutations allowed; visual invalidations coalesce | User callback errors are reported; current frame is aborted or an error subtree is scheduled |
| Build | At least one active `Element` is dirty, or root inflation/reassemble requires it | `markNeedsBuild`, dependency change, widget update, hot reload | No dirty elements | Widget configuration and persistent `Element` tree | `BuildOwner` owns dirty queue; elements own child references | Parent-before-child dirty processing; one active element is rebuilt at most once unless dirtied again by an allowed descendant build | Normally once per element; a bounded second visit is allowed only when re-dirtied during the same build scope | Failing subtree is replaced by/reportable error output; dirty queues remain consistent |
| Element reconciliation | A build returns a new widget configuration | Widget identity/type/key changes | Widget instance is identical and slot unchanged | Element identity, key registry, inactive element pool | `BuildOwner` and parent `Element` | `runtimeType + key` controls update compatibility; removed elements are deactivated then finalized | Once per rebuilt parent | Partial child mutations MUST be rolled back or leave a valid active/inactive tree |
| Layout | Root constraints changed or a render object is layout-dirty | `markNeedsLayout`, child list/parent data change, resize, intrinsic dependency | Constraints are value-equal and node is clean | Constraints, size, parent data offsets, layout caches | Each `RenderObject`; queue owned by `PipelineOwner` | Constraints flow down; sizes flow up; every laid-out object ends with a finite constrained size | Once per object in ordinary flow; additional passes only for explicitly documented layout callbacks, bounded by convergence guard | Object receives a constrained fallback size and paints an error box; frame may continue |
| Paint | Visual content is dirty, layout changed, first frame, or full repaint is required | `markNeedsPaint`, layout, style/content mutation, cache invalidation | Node is clean and a valid cached layer is composited | Paint-local data and repaint-boundary layer buffers | Render object / layer owner | Painting is clipped, deterministic for the same state, and may write only through `TerminalCanvas` | Once per dirty paint root or dirty repaint boundary | Failing object paints an error box inside its bounds; prior front buffer remains valid |
| Layer composition | Layer contents or placement/compositing properties changed | `markNeedsCompositing`, repaint-boundary paint, offset/clip/opacity/image placement change | No layer changed and root buffer can be reused | Repaint-boundary buffers, layer metadata, image overlays | Layer owner; frame composer borrows references | Child layers are composited in stable paint order with explicit clipping | Once per frame | Invalid layer is excluded or replaced by an error layer; cache is not promoted |
| Damage calculation | Paint/composition produced changes or hardware scroll altered the baseline | Dirty render bounds, changed layers, image cleanup, scroll request | No visual change and previous frame exists | Damage rectangles, row spans, optional row hashes | Frame composer | Damage conservatively covers every cell that may differ; false positives allowed, false negatives forbidden | Once per frame after composition | Falls back to full-screen damage |
| Terminal diff | A new composed frame must be compared with the physical baseline | Damage set, first frame, resize, image/scroll operations | Damage set is empty and no cursor/image cleanup is pending | Previous/front buffer, next/back buffer, encoded run builder | `TerminalBinding` | Wide cells, removals, styles, links, images, and cursor state remain correct | Once per frame | Falls back to full redraw when safe; otherwise frame is not committed |
| Single batched stdout write | Diff payload is complete | Any emitted terminal operation | Entire frame is visually empty and no terminal-state command is pending | Encoded frame payload | Backend during `present` | One logical presentation transaction; synchronized output when supported; one final flush | Exactly once | Front/back swap occurs only after success; cleanup path restores terminal modes |

## Dirty APIs

The renderer defines four independent invalidation APIs:

```dart
markNeedsBuild();
markNeedsLayout();
markNeedsPaint();
markNeedsCompositing();
```

Their contracts are:

- `markNeedsBuild` dirties one active element and schedules a frame. It does not
  directly dirty ancestors or descendants.
- `markNeedsLayout` dirties the render object, implies paint, and propagates toward
  the nearest layout boundary or root as required by parent-size dependencies.
- `markNeedsPaint` dirties the render object and propagates to the nearest repaint
  boundary or root.
- `markNeedsCompositing` dirties layer metadata and propagates to the nearest
  compositing boundary or root. It does not imply descendant repaint when cached
  layer content remains valid.

All four operations MUST be idempotent. Repeating a mark while already dirty MUST
still ensure that a frame is scheduled, but MUST NOT duplicate queue entries.

The current development implementation exposes `markNeedsBuild`,
`markNeedsLayout`, and `markNeedsPaint`. `markNeedsCompositing` is a required 1.0
contract and is currently an implementation gap.

## Cell contract

The normative cell model is:

```dart
class TerminalCell {
  Grapheme grapheme;
  Color foreground;
  Color background;
  TextAttributes attributes;
  int width;
  CellKind kind;
}
```

The complete Unicode, continuation-cell, transparency, overlap, hyperlink,
selection, and image-placeholder rules are defined in
[`cell-buffer.md`](rendering/cell-buffer.md).

The current implementation uses mutable `Cell { char, style,
isImagePlaceholder }` objects and `\u200B` continuation markers. The stable API
MUST either migrate to `TerminalCell` or provide an equivalent representation with
the same observable semantics.

## Damage contract

Damage is represented as zero or more clipped rectangles plus row-local spans.
The implementation MUST:

- track multiple disjoint damaged regions;
- merge overlapping or adjacent regions when cheaper;
- maintain optional row hashes to reject unchanged rows quickly;
- keep repaint-boundary damage local until composition;
- choose between sparse runs, whole-row rewrite, and full-screen redraw using a
  deterministic cost model;
- cap region count and fall back to a coarser region when the cap is exceeded;
- expose `paintedCells`, `comparedCells`, `writtenCells`, `damageRegions`,
  `ansiRuns`, and `outputBytes` per frame.

The current development implementation has reusable front/back buffers, per-row
dirty spans, cached repaint-boundary buffers, partial boundary painting, and
cost-aware ANSI runs. Multiple disjoint spans per row, row hashes, and the formal
region cap are planned gaps.

## Memory ownership

- Application state is owned by the application.
- Widgets are immutable configurations and may be short-lived.
- Elements persist across compatible rebuilds and are owned by the element tree.
- Render objects are owned by their `RenderObjectElement`.
- The `BuildOwner` owns the dirty-element queue, inactive pool, and global-key
  registry.
- The `PipelineOwner` owns layout, paint, compositing, and scroll-request queues.
- Repaint-boundary layer buffers are owned by the boundary and released on dispose.
- Front/back frame buffers are owned by the terminal binding and reused.
- Encoded frame payload memory is owned by one presentation transaction and
  released after success or failure.
- Backends MUST NOT retain mutable frame buffers after `present` returns.

## Reentrancy and scheduling

A stage MUST NOT recursively enter itself. Dirty work created during a stage is
queued according to these rules:

- build dirtied during build MAY be processed later in the same build scope only
  when ordering remains parent-before-child;
- layout dirtied during an allowed layout callback MAY be merged into the current
  layout pass;
- paint or compositing dirtied during paint is deferred to the next frame;
- a new event arriving during presentation is queued for a later frame;
- frame scheduling is coalesced and frame-rate limiting MUST NOT lose dirty work.

## Exception and rollback policy

The renderer is fail-soft at subtree boundaries and fail-closed at terminal
presentation:

- build/layout/paint failures SHOULD produce an error subtree or error box;
- diff/composition failures MUST preserve the previous physical baseline;
- backend write failure MUST NOT swap buffers;
- a failed cached layer MUST NOT replace its last known-good cache;
- uncaught fatal errors MUST restore cursor visibility, mouse mode, bracketed
  paste, keyboard protocol, styles, scroll region, synchronized-output mode, and
  alternate-screen state.

## Documents

- [Rendering overview](rendering/overview.md)
- [Frame pipeline](rendering/frame-pipeline.md)
- [Cell buffer and Unicode contract](rendering/cell-buffer.md)
- [Damage tracking](rendering/damage-tracking.md)
- [Layout and paint](rendering/layout-and-paint.md)
- [Compositing and cached layers](rendering/compositing.md)
- [Terminal diff and presentation](rendering/terminal-diff.md)
- [Images](rendering/images.md)
- [Hardware scroll regions](rendering/scroll-regions.md)
- [Performance contract](rendering/performance-contract.md)
- [Custom render objects](rendering/custom-render-objects.md)
