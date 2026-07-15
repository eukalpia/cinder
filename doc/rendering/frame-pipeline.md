# Frame pipeline

This document expands the stage matrix in [`../renderer.md`](../renderer.md).

## 1. Input and event collection

The backend decodes byte streams into logical keyboard, mouse, paste, resize, focus, signal, and protocol-response events.

Requirements:

- escape sequences MUST be parsed as complete events;
- malformed or stale partial input MUST not block later valid input forever;
- consecutive input bytes MAY be batched before dispatch;
- event ordering from one backend stream MUST be preserved;
- event dispatch MUST not present a frame directly.

Input handlers may mutate state and mark work dirty. After a batch of events, the scheduler decides whether a frame is required.

## 2. State mutation

State mutation includes `State.setState`, controller/listenable notifications, stream/future completion, animation ticks, focus/selection/scroll changes, and terminal resize/capability changes.

A mutation callback SHOULD be synchronous and small. Async work MUST complete outside rendering phases and then schedule a mutation.

A state mutation chooses the narrowest invalidation:

```text
configuration/dependency changed      → markNeedsBuild
geometry/constraints changed          → markNeedsLayout
visible cells changed                 → markNeedsPaint
layer placement/effect changed        → markNeedsCompositing
```

Over-invalidating is correct but slower. Under-invalidating is a correctness bug.

## 3. Build

`BuildOwner` processes active dirty elements in parent-before-child depth order.

Build requirements:

- one dirty-list entry per element;
- inactive/defunct elements are skipped and removed safely;
- a clean child whose widget is reusable remains mounted;
- building MUST NOT write cells or terminal output;
- build output is a widget configuration, not a render result;
- elements dirtied during build are re-sorted deterministically.

A normal element is rebuilt at most once per frame. An element MAY be rebuilt a second time only when an allowed dependency mutation dirties it after its first visit and ordering remains valid. A convergence guard MUST abort pathological rebuild loops.

## 4. Element reconciliation

For each rebuilt parent, reconciliation compares old elements with new widgets.

Compatibility is:

```dart
oldWidget.runtimeType == newWidget.runtimeType &&
oldWidget.key == newWidget.key
```

Compatible widgets update an existing element. Incompatible widgets deactivate the old element and inflate a new one. Keyed children retain identity across reorder. Unkeyed middle children may be replaced.

Reconciliation MUST leave valid parent pointers, valid slots, a unique global-key registry, render children in slot order, and removed elements in the inactive pool until finalization.

## 5. Layout

Layout starts at the root with tight terminal-size constraints or at dirty layout roots with established parent constraints.

A render object can skip layout when:

```text
needsLayout == false
AND newConstraints == previousConstraints
```

`performLayout` MUST lay out required children, write parent-data offsets, set a finite constrained size, avoid terminal output, and avoid application-visible async work.

Layout-created dirtiness from a documented layout callback may be merged into the current pass. Ordinary invalidation of an already processed ancestor is deferred or treated as a convergence error.

## 6. Paint

Paint converts render state into cells through `TerminalCanvas`.

Paint roots are the root render object for first/full paint and topmost dirty repaint boundaries for safe partial paint.

Paint MUST be deterministic, clipped, and side-effect-free except for writes to the target canvas and frame-local metadata. It MUST not emit ANSI, flush stdout, mutate application state, or schedule async work.

A valid cached repaint layer permits descendant paint to be skipped.

## 7. Layer composition

Composition combines root paint content, repaint-boundary buffers, clips/offsets, image overlay metadata, selection/debug overlays, and terminal cursor intent.

Layer content and layer placement are different invalidations. Moving a valid cached layer SHOULD require composition and damage but not descendant paint.

The current implementation composes cached boundary buffers during paint. The specification treats composition as a distinct logical phase.

## 8. Damage calculation

Damage converts dirty render/layer bounds into terminal-space rectangles and row-local spans.

Rules:

- damage is clipped to the screen;
- old and new bounds are damaged when an object moves or shrinks;
- wide-grapheme leading and continuation cells are damaged together;
- image cleanup regions are included;
- hardware-scroll exposed rows are included;
- overlapping/adjacent rectangles may be merged;
- exceeding the region limit coarsens damage, eventually to full-screen.

Damage calculation MUST occur after composition and before diff.

## 9. Terminal diff

The diff compares the new composed frame with the last successfully presented front buffer, restricted to conservative damage.

It chooses among no output, sparse cursor-positioned runs, merged runs spanning cheap unchanged gaps, whole-row rewrite, and full-screen redraw.

The encoder handles style transitions, wide cells, hyperlinks, image placeholder boundaries, clearing removed content, and final cursor placement.

## 10. Single batched presentation

All operations for a frame are accumulated in order:

```text
begin synchronized output (when supported)
hardware scroll operations
cell diff/full redraw
image cleanup
image placement
style reset
final IME/application cursor
reset scroll region
end synchronized output
```

The completed payload is submitted once:

```dart
await backend.present(framePayload);
```

The backend MAY internally handle platform-specific partial system writes, but the renderer exposes exactly one logical presentation.

Only after success does the binding promote the back buffer, commit image state, clear damage, and recycle the old front buffer. On failure the previous front buffer remains authoritative.

## Phase legality

| Operation | Input | Build | Layout | Paint | Compose | Diff/present |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Mutate application state | Yes | Restricted | No | No | No | No |
| `markNeedsBuild` | Yes | Yes, queued | Deferred | Deferred | Deferred | Deferred |
| `markNeedsLayout` | Yes | Yes | Restricted | Deferred | Deferred | Deferred |
| `markNeedsPaint` | Yes | Yes | Yes | Next frame | Next frame | Next frame |
| Write cells | No | No | No | Yes | Layer blit only | No |
| Write terminal bytes | No | No | No | No | No | Present only |

## Exception boundaries

- Input parser error: discard malformed unit and continue.
- Event-handler error: report and schedule an error surface where possible.
- Build error: preserve tree consistency and mount an error widget/subtree.
- Layout error: assign fallback constrained size and mark an error box.
- Paint error: paint an error box inside known bounds.
- Composition/damage error: abandon provisional frame and schedule full repaint.
- Diff error: abandon provisional frame.
- Present error: do not swap buffers; initiate terminal recovery/cleanup.

## Frame-finalization order

After successful presentation:

1. update front/back buffer ownership;
2. commit active image overlays;
3. finalize inactive elements;
4. run post-frame callbacks;
5. clear per-frame metrics/queues;
6. return scheduler phase to idle.

Post-frame callbacks cannot modify the frame already presented; they may schedule another frame.
