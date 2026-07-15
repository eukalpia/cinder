# Frame pipeline

Status: **normative**.

A frame is a transaction that converts previously committed state plus queued input into
one terminal output batch. Stages MUST execute in the order below. A stage MAY be skipped
only under the explicit conditions in this document.

## Stage contract matrix

| Stage | Runs when | Dirtied or requested by | May be skipped when | Cache / memory owner | Maximum successful executions per frame | Exception policy |
|---|---|---|---|---|---|---|
| Input / Event | input queue is non-empty | terminal backend, timers, signals, pointer/keyboard input | yes, when no event is queued | input binding owns queue and decoded events | each event once | report callback failure; continue remaining events unless binding integrity is lost |
| State mutation | an event/timer callback mutates application state | `setState`, controllers, listenables, focus/scroll changes | yes | state owner is the application/controller that exposes it | unbounded mutations, but callbacks are serialized | mutation is retained; exception is reported; no implicit rollback |
| Build | at least one element is build-dirty | `markNeedsBuild`, dependency changes, parent reconciliation | yes | build owner owns dirty element queue | one successful rebuild per element per build epoch | preserve last valid subtree or install error subtree; schedule recovery frame |
| Element reconciliation | a build returns a widget configuration | successful build or root replacement | yes | element tree owns identity and slots | once per rebuilt element | partial reconciliation MUST NOT leak mounted orphan elements |
| Layout | root constraints changed or render objects are layout-dirty | `markNeedsLayout`, child list changes, parent data, terminal resize | yes | render objects own geometry; pipeline owns dirty queue | one normal pass plus one stabilization pass | contain at failing render object, assign bounded fallback size, mark paint damage |
| Paint | paint-dirty root/boundary exists or full repaint is required | `markNeedsPaint`, layout, layer invalidation, debug modes | yes | repaint boundary owns cached local surface; frame binding owns target buffer | each repaint boundary once; root once | paint an error surface inside the same clip; never publish partially initialized cells |
| Layer composition | layer tree changed, a layer is dirty, or painted layers must be placed | `markNeedsCompositing`, paint output, transform/opacity/clip changes | yes only when final back buffer is already synchronized and no layer changed | compositing owner owns layer graph and caches | once per layer; one root composition | abort frame, preserve front buffer, force full repaint next frame |
| Damage calculation | composition produced local or global damage | paint/layer damage, removed content, image changes, scroll mutation | yes only for a proven no-op frame | pipeline owns region set and row summaries | once | abort frame and force full-frame damage next frame |
| Terminal diff | damage set is non-empty or terminal is desynchronized | damage calculation, resize, backend recovery | yes for empty damage and no control output | terminal binding owns front/back buffers and encoder | once | abort commit; mark terminal desynchronized; retain previous front buffer |
| Batched stdout write | diff/control batch contains bytes | terminal diff | yes when batch is empty | backend owns transport; binding owns pending bytes until accepted | exactly one visual write | keep old front buffer; backend enters recovery state |

## 1. Input / Event

Input decoding MUST finish before application callbacks are invoked. One decoded event is
immutable for its dispatch lifetime. Pointer button state, keyboard modifiers, terminal
size, and protocol capability changes MUST be normalized before hit testing or shortcut
routing.

Event callbacks run serially on the UI isolate. Reentrant frame execution is forbidden:
an event MAY schedule a frame but MUST NOT directly call the full render pipeline.

High-frequency pointer motion MAY be coalesced, but press, release, wheel, focus, resize,
and key events MUST preserve order.

## 2. State mutation

State mutation is not itself a rendering stage with owned memory. It changes data owned by
widgets, controllers, models, or inherited state and marks the appropriate framework node
dirty.

A mutation MUST choose the narrowest invalidation:

- configuration/dependency change: `markNeedsBuild`;
- geometry change: `markNeedsLayout`;
- visual-only change: `markNeedsPaint`;
- transform/opacity/clip/layer topology change: `markNeedsCompositing`.

Using a broader invalidation is correct but a performance defect. Using a narrower
invalidation that leaves stale output is a correctness defect.

## 3. Build

The build owner snapshots the dirty element queue at the start of a build epoch. Parents
are rebuilt before descendants. An element already rebuilt in the current epoch MUST NOT
be rebuilt again; a new dirty mark schedules the next epoch/frame.

Build MAY be skipped when:

- no element is dirty;
- no inherited dependency changed;
- no root widget replacement is pending.

Build caches immutable widget configurations only through the mounted element tree.
Widgets MUST NOT own framebuffer, layer, or render-object memory.

On a build exception, the framework MUST report the element, widget type, frame ID, and
stack trace. It MUST either keep the previous valid subtree or replace the failed subtree
with a bounded error widget. Mounted orphan elements are forbidden.

## 4. Element reconciliation

Reconciliation compares runtime type and key, updates compatible elements, mounts new
ones, moves keyed children, and deactivates removed ones. Slots and parent data MUST be
updated before layout.

Reconciliation is complete before layout begins. A render object MUST NOT observe a child
list that is half old and half new.

The element tree owns reconciliation memory. Temporary keyed-child maps are frame-local
and MUST be released after the update.

## 5. Layout

Layout starts from the shallowest dirty relayout boundaries. Constraints flow down; sizes
and parent positions flow up. See [layout-and-paint.md](layout-and-paint.md).

A clean render object with value-equal constraints MUST skip `performLayout`. A child MAY
still be laid out by its parent if its constraints changed.

If layout code marks new nodes dirty, one stabilization pass is allowed. Work that would
require a third pass MUST be deferred to the next frame and reported in debug mode as a
layout-cycle violation.

## 6. Paint

Paint records resolved cell operations into a layer-local or frame-local surface. Paint
MUST be deterministic and side-effect free outside its owned cache and diagnostics.

A clean repaint boundary MUST be composited from cache without walking descendants.
Layout always implies paint damage for the old and new occupied bounds.

Paint MUST NOT write to stdout, query terminal capabilities, mutate application state, or
retain the canvas.

## 7. Layer composition

Composition resolves transforms, clips, opacity, overlap, selection decoration, and image
planes into the back framebuffer. See [compositing.md](compositing.md).

The result of composition MUST be a complete logical terminal frame for every damaged
cell. No unresolved transparency, dangling wide continuation, or partially covered image
region may reach terminal diff.

## 8. Damage calculation

Damage is calculated from:

- layer-local paint damage transformed into root coordinates;
- previous and current bounds of moved/resized layers;
- deleted content;
- wide-grapheme expansion;
- image placement/removal;
- accepted hardware scroll mutations;
- terminal resize or desynchronization.

Damage calculation produces a bounded region set plus per-row spans/hashes. See
[damage-tracking.md](damage-tracking.md).

## 9. Terminal diff

Terminal diff compares the committed front buffer with the composed back buffer only in
candidate damaged rows/regions, with row hashes used to reject unchanged rows quickly.
It emits cursor movement, style transitions, text, hyperlink, image, and scroll commands.
See [terminal-diff.md](terminal-diff.md).

## 10. Single batched stdout write

All frame-scoped bytes MUST be accumulated into one contiguous output batch:

```text
begin synchronized output
scroll-region mutations, if any
cell/style/hyperlink diff
image protocol commands
final cursor/IME position
end synchronized output
```

The binding MUST invoke the backend's visual write exactly once for a non-empty frame.
Calling `flush`, `writeRaw`, or an equivalent transport operation from build, layout,
paint, composition, or diff helpers is forbidden.

Shutdown, capability negotiation, and emergency terminal reset are out-of-band operations.
They MUST serialize with visual frames and MUST NOT interleave bytes inside a frame batch.

## Frame commit

The frame commits only after the backend accepts the complete batch. On commit:

1. back buffer becomes front buffer;
2. the previous front buffer becomes reusable scratch storage;
3. committed layer revisions advance;
4. dirty queues and damage sets for the frame are cleared;
5. metrics are published.

If output fails, none of those commit actions may occur.
