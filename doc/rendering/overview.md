# Rendering overview

Status: **normative**.

This section defines Cinder's rendering model from an input event to the bytes written
to the terminal. It is intentionally stricter than the current implementation. A
feature marked "required next" is part of the contract even when the current code has
not completed it yet.

## Goals

Cinder's renderer MUST provide:

1. deterministic output for the same widget tree, terminal capabilities, and input;
2. Unicode-safe cell ownership, including wide and joined grapheme clusters;
3. bounded work for local changes;
4. stable layer and framebuffer memory ownership;
5. one atomic visual write per frame;
6. failure containment without corrupting the terminal's front buffer;
7. public contracts that make custom render objects safe to implement.

## Canonical pipeline

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

The pipeline is pull-driven by a scheduled frame. Dirty marking only records work and
requests a frame; it MUST NOT synchronously execute a later stage unless the API is
explicitly documented as an immediate layout callback.

## Tree ownership

| Object | Owner | Lifetime | Mutable state owned |
|---|---|---|---|
| `Widget` | application | immutable value lifetime | configuration only |
| `Element` | framework/build owner | mounted tree lifetime | reconciliation identity, dependencies, build dirtiness |
| `RenderObject` | element/render tree | mounted render lifetime | constraints, size, parent data, layout/paint dirtiness |
| `Layer` | compositing owner or repaint boundary | cache lifetime | local cell surface, transform, opacity, local damage |
| frame buffers | terminal binding | terminal-size epoch | front/back `TerminalCell` storage and metadata planes |
| diff encoder | terminal binding | frame or reusable encoder lifetime | cursor/style state and output byte buffer |

No stage MAY retain a borrowed object past its documented lifetime. In particular,
paint code MUST NOT retain a `TerminalCanvas`, and terminal diff code MUST NOT mutate
the committed front buffer.

## Current implementation and required evolution

Cinder already has:

- reusable flat front/back cell buffers;
- per-row dirty spans;
- idempotent `markNeedsLayout` and `markNeedsPaint`;
- layout skipping when constraints are value-equal and the node is clean;
- cached repaint-boundary buffers;
- synchronized terminal output;
- guarded terminal scroll-region acceleration;
- inline-image metadata carried beside placeholder cells.

The contract additionally requires:

- the canonical `TerminalCell` and metadata-plane model;
- `markNeedsCompositing` and explicit compositing dirtiness;
- multiple damage rectangles and layer-local damage;
- bounded region coalescing and row hashes;
- a cost model for region, row, and full-frame redraw;
- complete per-frame renderer statistics;
- transactional handling of composition/diff/write failures.

## Frame identity

Every scheduled visual frame has a monotonically increasing `frameId`. All dirty marks,
metrics, layer revisions, and exceptions MUST be attributable to a frame ID. A frame is
one of:

- **committed**: one complete output batch was accepted by the backend and the back
  buffer became the new front buffer;
- **skipped**: no visual work remained after coalescing;
- **aborted**: a fatal composition, diff, or output error prevented commit.

An aborted frame MUST NOT replace the previous front buffer.

## Coordinate spaces

The renderer distinguishes:

1. local render-object coordinates;
2. layer-local coordinates;
3. logical terminal-cell coordinates;
4. backend output coordinates.

Damage rectangles are half-open integer cell rectangles in the coordinate space named
by their owner. Conversion MUST round outward so no touched cell is omitted. Fractional
layout positions are allowed internally, but paint and damage resolve to integer cells.

## Normative invariants

- A committed framebuffer contains no unresolved transparency.
- A wide grapheme has exactly one lead cell and one continuation cell.
- Damage always includes both cells of any wide grapheme it intersects.
- A repaint boundary is painted at most once per frame.
- Terminal diff is executed at most once per committed frame.
- A visual frame produces exactly one backend write.
- The front buffer changes only after the backend write succeeds.
- Dirty marking is idempotent within a dirty epoch.
- Idle applications perform no build, layout, paint, diff, or visual stdout write.

## Reading order

Read [frame-pipeline.md](frame-pipeline.md) first, then
[cell-buffer.md](cell-buffer.md), [damage-tracking.md](damage-tracking.md), and
[performance-contract.md](performance-contract.md). The remaining documents specify
individual subsystems.
