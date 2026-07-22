# Rendering overview

This document describes the architecture and ownership model behind the Cinder renderer. [`../renderer.md`](../renderer.md) is the normative entry point.

## Architecture

Cinder uses four persistent trees/state domains:

```text
Widget configurations
        ↓ inflate/update
Element tree
        ↓ creates/updates
Render-object tree
        ↓ paints into
Layer/frame buffers
        ↓ diff/present
Physical terminal
```

Widgets are immutable descriptions. Elements preserve identity, lifecycle, keys, dependencies, and state across compatible widget updates. Render objects own layout and paint behavior. Frame and layer buffers own mutable terminal-cell storage.

## Core invariants

- The element tree and render tree MUST remain structurally valid between frames.
- A render object MUST have at most one render parent.
- An active render object MUST be attached to exactly one `PipelineOwner`.
- Constraints flow from parent to child.
- Size and baseline information flow from child to parent.
- Paint order is stable and follows render-child order.
- Later paint operations overwrite earlier cell content unless a defined blend operation is used.
- Every buffer mutation that may affect presentation MUST create conservative damage.
- Front-buffer contents describe the last successfully presented terminal state.
- Back-buffer contents are provisional until presentation succeeds.

## Coordinate systems

Cinder uses terminal-cell coordinates.

- The physical screen origin is `(0, 0)`, top-left.
- X grows right; Y grows down.
- Layout sizes and offsets may use `double` for API compatibility, but paint and damage MUST resolve to integer terminal cells deterministically.
- Default rounding is nearest-cell for offsets and outward rounding for damage rectangles.
- A clip rectangle is half-open: `[left, right) × [top, bottom)`.
- A wide grapheme occupies its leading coordinate and exactly one continuation coordinate.

Nested canvases translate local coordinates into the parent buffer. A custom render object MUST NOT address cells outside the canvas clip.

## Frame model

A frame is scheduled when any of the following occurs:

- an element becomes build-dirty;
- a render object becomes layout-, paint-, or compositing-dirty;
- terminal size/capability state changes;
- an animation ticker requests a frame;
- an image cleanup or scroll request requires terminal output;
- the root is mounted or reassembled.

A scheduled frame MAY be delayed by frame-rate limiting, but dirty work MUST not be discarded. Multiple schedules coalesce.

A frame can be entirely skipped when there is a valid previous buffer and no build, layout, paint, compositing, cursor, image, cleanup, or terminal-state work.

## Ownership and lifetime

| Object | Owner | Lifetime |
| --- | --- | --- |
| `Widget` | Application/build call | Until no references remain |
| `Element` | Parent element / root binding | Compatible rebuilds |
| `State` | Stateful element | Mount to dispose |
| `RenderObject` | Render-object element | Element mount to unmount/dispose |
| Dirty build queue | `BuildOwner` | Application binding |
| Layout/paint/compositing queues | `PipelineOwner` | Application binding |
| Repaint layer | Repaint boundary | Boundary size/cache lifetime |
| Front/back buffers | `TerminalBinding` | Reused until resize/shutdown |
| Image overlay metadata | Buffer and image cleanup manager | Visible placement lifetime |
| Frame payload | Presentation transaction | One frame |
| Physical baseline | Terminal binding | Last successful presentation |

Mutable cells MUST NOT be shared between simultaneously writable buffers. Cached layers MAY be blitted into a frame buffer but MUST not be mutated by the blit.

## Current implementation mapping

The current renderer already provides:

- immutable widgets, persistent elements, and render objects;
- `BuildOwner` and `PipelineOwner`;
- value-based layout skipping;
- mutable flat `Buffer` storage;
- reusable front/back buffers;
- per-row dirty spans;
- repaint-boundary cached buffers;
- partial repaint of topmost dirty boundaries;
- cost-aware terminal runs;
- synchronized-output framing;
- terminal scroll requests;
- image placeholder cells and overlay metadata.

The 1.0 specification additionally requires:

- explicit `TerminalCell`/`CellKind` semantics;
- `markNeedsCompositing`;
- multiple disjoint damage regions/spans;
- row hashes;
- an explicit frame-output builder and one presentation call;
- formal queue/pass limits and convergence guards;
- stable per-frame metrics and release gates.

## Layered responsibility

The renderer is split into these conceptual layers:

1. **Framework layer** — widgets, elements, reconciliation, build ownership.
2. **Layout layer** — constraints, sizes, parent data, hit-test geometry.
3. **Paint layer** — clipped writes into logical cells.
4. **Composition layer** — cached layers, image overlays, placement.
5. **Damage layer** — changed bounds and row-local spans.
6. **Diff layer** — previous/current cell comparison and ANSI encoding.
7. **Backend layer** — one atomic presentation transaction and terminal cleanup.

A higher layer MUST NOT bypass lower-layer contracts. In particular, widgets and render objects MUST NOT write ANSI directly.

## Threading and isolates

The primary UI pipeline is single-threaded and ordered. Background isolates MAY perform parsing, image decoding, syntax highlighting, or application work, but they MUST deliver immutable results to the UI isolate. They MUST NOT mutate the element tree, render tree, buffers, layer cache, focus tree, or terminal backend.

## Determinism

Given equal terminal dimensions/capabilities, widget/application state, event order, width policy, and previous physical baseline, the renderer SHOULD produce identical logical cells and equivalent terminal output. Timing-dependent animation values are explicit inputs.

## Compatibility principle

Terminal capabilities affect encoding, not application semantics. Unsupported features MUST degrade safely:

- true color → 256/16 color quantization;
- protocol image → Unicode cell image;
- hardware scroll → ordinary damage repaint;
- synchronized output → one buffered write without the private mode;
- hyperlink → styled plain text;
- transparency → resolved opaque cell colors.
