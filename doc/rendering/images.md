# Images

Status: **normative**.

Inline images are terminal overlays with cell-space ownership. They are not ordinary text
cells, but they participate in layout, clipping, damage, composition, diff, and lifecycle.

## Logical image region

An image region has:

- stable `ImageRegionId`;
- protocol (`kitty`, `iterm2`, `sixel`, or a documented fallback);
- root or layer-local cell rectangle;
- content revision/hash;
- protocol resource ID when supported;
- encoded payload or reusable resource reference;
- z-order and clip;
- lifecycle state: absent, create, visible, update, move, delete.

Covered framebuffer cells use `CellKind.imagePlaceholder` and reference the same region ID
through the image metadata plane.

## Ownership and overlap

Image ownership is rectangular unless a protocol-specific mask is explicitly supported.
Text or another image painted above the region removes ownership for the overlapped cells.
A partially occluded image MAY require full delete/recreate when the protocol cannot express
clipped placement.

Placeholder cells never emit text. Selection and text copy exclude them unless the widget
provides alternative semantics.

## Damage

Creating, moving, resizing, updating, clipping, covering, uncovering, or deleting an image
damages both old and new visible bounds. Protocol deletion commands are included even when
new cells are visually blank.

Layer caching carries image metadata with the cached surface. A layer blit must translate
image regions and reject partially contained regions unless the protocol supports clipping.

## Protocol lifecycle

### Kitty

Kitty resources SHOULD use stable image IDs. Content upload, placement, movement, and deletion
are separate lifecycle operations when supported. The committed registry tracks uploaded
content and visible placements.

### iTerm2

iTerm2 inline images are generally cursor-positioned payloads without a fully independent
placement lifecycle. Movement or overlap MAY require repainting the containing region and
clearing old cells.

### Sixel

Sixel mutates terminal pixels relative to cursor position. The renderer MUST treat its region
as requiring conservative clear/repaint. Scroll acceleration is disabled for intersecting
Sixel regions unless terminal-specific proof exists.

### Unicode fallback

Unicode/block fallback paints ordinary text cells and follows the standard cell contract;
it is not represented as an image placeholder region.

## Scroll safety

A hardware scroll request intersecting any active protocol image is rejected by default.
A protocol/terminal profile MAY allow scrolling only when both terminal pixels and the
committed image registry are known to move identically.

## Resize and capability changes

Terminal resize, cell-pixel-size change, image-protocol capability change, or width-profile
change invalidates image placement. The renderer deletes or abandons old protocol resources
safely, clears affected bounds, and reconstructs visible images in the next full frame.

## Output batching

Image commands are emitted inside the frame's single output batch. An image helper MUST NOT
write directly to the backend. Payload size does not relax the one-write contract; the
backend API must accept the complete batch or provide an atomic gather-write abstraction
that is observed as one visual write.

## Failure handling

If image encoding fails, the affected widget paints a documented fallback or bounded error
surface. If protocol output fails, the entire frame does not commit and terminal state becomes
desynchronized.

The next recovery frame clears uncertain image regions and reconciles the committed resource
registry before normal diff.

## Metrics

Track uploaded bytes, reused resources, placements, deletes, fallback renders, image-covered
cells, image damage expansions, and scroll requests rejected because of images.
