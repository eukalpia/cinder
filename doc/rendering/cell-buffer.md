# Cell buffer contract

Status: **normative**.

The cell model is the renderer's Unicode and compositing ABI. Implementations MAY optimize
storage, but every public and internal operation MUST behave as if the canonical model
below were used.

## Canonical logical cell

```dart
final class TerminalCell {
  Grapheme grapheme;
  Color foreground;
  Color background;
  TextAttributes attributes;
  int width;
  CellKind kind;
}
```

`Grapheme` is one Unicode extended grapheme cluster, not a UTF-16 code unit, Unicode scalar,
or terminal byte sequence.

```dart
enum CellKind {
  text,
  wideContinuation,
  empty,
  imagePlaceholder,
}
```

### Field invariants

- `width` MUST be `1` or `2` for `CellKind.text`.
- `width` MUST be `0` for `CellKind.wideContinuation`.
- `width` MUST be `1` for `CellKind.empty` and `CellKind.imagePlaceholder`.
- `grapheme` MUST be non-empty only for `CellKind.text`.
- a `wideContinuation` MUST immediately follow a width-2 `text` cell in the same row;
- the last column of a row MUST NOT contain a width-2 lead cell;
- the committed frame MUST NOT contain unresolved alpha in foreground or background.

The current `Cell` class is an implementation type. It MUST migrate toward this logical
contract; its use of a zero-width-space continuation is not the normative representation.

## Metadata planes

Hyperlink, selection, semantics, and image-region data MUST NOT enlarge the hot
`TerminalCell` object by default. They are stored in frame-sized or sparse sidecar planes
keyed by linear cell index:

```dart
final class CellMetadataPlanes {
  HyperlinkId? hyperlinkAt(int index);
  SelectionState selectionAt(int index);
  ImageRegionId? imageRegionAt(int index);
  Object? semanticsAt(int index);
}
```

An implementation MAY inline metadata when profiling proves it cheaper, but observable
behaviour MUST remain identical.

## Wide characters

A width-2 grapheme occupies two terminal columns:

```text
[index N]     kind=text, width=2, grapheme=<cluster>
[index N + 1] kind=wideContinuation, width=0, grapheme=empty
```

The continuation cell is owned by the lead cell. It is not independently paintable,
selectable, hyperlinkable, or diffable.

Any operation that writes, clears, clips, selects, or damages either half MUST first expand
to the full two-cell cluster. Overwriting a continuation cell MUST clear the previous lead
cell before installing the new content. Overwriting a lead cell MUST clear its old
continuation even when the replacement is width 1.

A width-2 cluster that would start in the final column is clipped as a whole. The renderer
MUST clear stale content in the final column and MUST NOT emit a half glyph. Debug mode MAY
paint a width-1 replacement marker, but production output defaults to clipping.

## Combining marks

Input text is segmented using Unicode extended grapheme cluster rules before width
calculation. Combining marks belonging to a base character remain in the same `Grapheme`.

A cluster whose computed terminal width is zero MUST be handled as follows:

1. if a preceding text lead exists in the same logical text run, append the cluster to it
   and recompute the lead width;
2. otherwise prefix U+25CC DOTTED CIRCLE and treat the result as a visible grapheme.

A zero-width cluster MUST NOT create an independently addressable cell.

## Emoji and ZWJ sequences

Emoji ZWJ sequences, variation selectors, skin-tone modifiers, and regional-indicator
flags are one `Grapheme` when Unicode segmentation says so. Width is resolved by a
`TerminalWidthProfile` captured for the frame.

The default profile MUST classify supported emoji presentation clusters as width 2.
Capability-specific overrides MAY classify a cluster differently, but the chosen width
MUST remain stable for the complete frame and for front/back comparison.

Changing the width profile invalidates the complete framebuffer and forces a full repaint.

## Foreground, background, and transparency

Paint surfaces MAY contain transparent channels while layers are being composed.
`Color.transparent` means "preserve the lower layer for this channel", not "emit the
terminal default color".

Composition resolves alpha in premultiplied form. The final framebuffer MUST contain an
opaque foreground/background pair or explicit terminal-default sentinels understood by
the diff encoder. Terminal diff MUST NOT perform alpha blending.

Text foreground on a fully transparent text cell is meaningless; such a cell MUST resolve
to `empty` unless an overlay metadata plane requires occupancy.

## Clipping

Clips are half-open cell rectangles. Painting outside a clip has no effect. A clip that
intersects only one half of a wide grapheme MUST exclude the complete grapheme unless the
lead and continuation both fit.

Clipping an old wide glyph during layer movement or resize still requires clearing both old
cells in the root damage set.

## Overlap

Layers are composited in paint order. Later layers win for opaque channels. Transparent
channels preserve lower content. Text occupancy is atomic at grapheme-cluster granularity:
a later width-1 cell that overlaps the continuation of an earlier wide glyph clears the
entire earlier glyph before it is placed.

Metadata resolution follows the visible topmost owner. Selection decoration MAY modify
colors/attributes after text overlap but before terminal diff.

## Clearing stale wide glyphs

Before writing a cell at `(x, y)`, the buffer MUST inspect:

- the existing cell at `(x, y)`;
- the previous cell when the existing cell is a continuation;
- the next cell when the existing cell is a width-2 lead;
- the next cell when the replacement is width 2.

Every invalidated member of an old cluster is reset and added to damage. This rule applies
to painting, buffer synchronization, layer blits, scroll mutations, and resize.

## Hyperlinks

Hyperlinks are represented by a stable `HyperlinkId` and a frame-local table containing URI
and optional terminal ID. All cells of a wide grapheme MUST have the same effective
hyperlink metadata through their lead ownership.

Terminal diff emits OSC 8 open/close transitions around maximal contiguous runs. A run MUST
be closed before cursor movement outside the run, style reset that would invalidate it, an
image command, synchronized-output end, or frame end.

## Selection

Selection metadata is a decoration plane, not a mutation of the source grapheme. The
selection compositor resolves selected foreground, background, and attributes into the
final cells. Copy operations read logical text ownership, not rendered continuation cells
or image placeholders.

A selected width-2 grapheme is selected atomically.

## Image placeholder cells

Every cell covered by an inline image region has `kind=imagePlaceholder` and references one
`ImageRegionId` in the image metadata plane. Placeholder cells:

- participate in clipping, overlap, damage, selection exclusion, and scroll safety;
- MUST NOT emit their placeholder grapheme through the text diff;
- are cleared when the image is removed or replaced;
- prevent hardware scroll acceleration unless the active protocol is proven safe.

Text painted above an image removes image ownership for the overlapped atomic region.
Protocol-specific lifecycle is defined in [images.md](images.md).

## Buffer storage

The framebuffer MUST use flat, reusable storage or an equivalent layout with O(1) indexed
access. Front and back storage are owned by the terminal binding for a terminal-size epoch.
Resize creates a new epoch and invalidates all row hashes, damage summaries, width-profile
assumptions, and image placements.

The buffer MUST expose logical operations rather than raw field mutation for writes that can
intersect wide glyphs. Direct mutation that bypasses cluster cleanup is forbidden.
