# Cell buffer and Unicode contract

The cell buffer is the renderer's canonical logical image of the terminal.

## Normative model

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

Suggested supporting types:

```dart
enum CellKind { empty, grapheme, continuation, imagePlaceholder }

final class Grapheme {
  const Grapheme(this.value);
  final String value;
}

final class TextAttributes {
  final bool bold;
  final bool dim;
  final bool italic;
  final bool underline;
  final bool strikeThrough;
  final bool reverse;
  final Uri? hyperlink;
  final SelectionMetadata? selection;
}
```

The exact public type shape MAY evolve before 1.0, but the observable semantics in this document are mandatory.

## Cell invariants

- `empty`: grapheme is one space, width `1`.
- `grapheme`: exactly one extended grapheme cluster, width `1` or `2`.
- `continuation`: no independently rendered grapheme, width `0`.
- `imagePlaceholder`: reserves one protocol-image cell, width `1`.
- A continuation MUST immediately follow a width-2 leading grapheme.
- A width-2 leading grapheme MUST have exactly one continuation in the same row.
- A row MUST never end with an unmatched width-2 leading grapheme.
- Alpha may exist during paint, but presented colors are deterministic/composited.

## Grapheme segmentation

Text MUST be segmented by Unicode extended grapheme clusters, not code points or UTF-16 units. This preserves combining sequences, emoji modifiers, variation selectors, ZWJ families/professions, regional-indicator flags, and other multi-code-point clusters.

## Width policy

One versioned Cinder policy determines width:

- `0` for isolated non-spacing/format clusters that cannot render independently;
- `1` for ordinary narrow clusters;
- `2` for wide/full-width clusters and policy-selected emoji.

The same policy MUST be used by layout, paint, hit testing, selection, cursor movement, diff, and tests. Ambiguous-width characters default to `1` unless an explicit terminal profile selects `2`.

## Combining marks

A combining mark inside an extended grapheme remains inside that grapheme. An isolated width-0 grapheme SHOULD attach to the preceding grapheme when text shaping has context; otherwise it is ignored without advancing. It MUST NOT allocate a standalone continuation.

## Emoji ZWJ

A ZWJ sequence is one grapheme. Width is resolved for the complete sequence. It MUST NOT be split across cells, clips, lines, or diff runs. If a width-2 sequence does not fit before the right clip edge, the whole grapheme is omitted or wrapped by text layout.

## Wide-character storage

A width-2 grapheme occupies:

```text
x     : CellKind.grapheme, width = 2, grapheme = "…"
x + 1 : CellKind.continuation, width = 0
```

The continuation is never emitted independently. It exists for damage, clearing, hit testing, selection, cursor movement, and overlap prevention.

The current implementation uses `\u200B` as an internal marker. This is compatible only while it is never observable as text and every path treats it as `CellKind.continuation`.

## Overwriting and wide-cell cleanup

Before writing a range, the buffer normalizes intersecting wide cells.

- Writing at an old width-2 leader clears both old positions.
- Writing at a continuation clears it and the preceding leader.
- Writing a new width-2 grapheme clears every old pair intersecting either target cell, then writes leader+continuation atomically.

This prevents stale right halves and corrupted columns.

## Clipping

Clips are half-open.

- Width-1 may paint when its leading cell is inside.
- Width-2 may paint only when both cells are inside.
- No continuation may be created outside the clip.
- Damage includes every old cell cleared by normalization, even when outside the requested write coordinate.

## Overlap and paint order

Later paint replaces earlier grapheme, attributes, link, and selection metadata in the affected range. Alpha is resolved against existing logical colors during paint. There is no undefined transparent terminal cell at presentation time.

`CellKind.empty` means a rendered blank with resolved/default style, not transparent memory.

## Foreground/background and attributes

`Color.defaultColor` is a semantic terminal default. Before encoding, alpha is composited, reverse semantics are handled consistently, selection may alter effective colors without mutating document style, and color downsampling occurs after composition.

Attributes participating in equality include bold, dim, italic, underline, strike-through when supported, reverse, hyperlink identity, and effective selection presentation. Unsupported attributes degrade without changing width.

## Hyperlink metadata

OSC 8 hyperlinks are metadata, never embedded escape sequences inside grapheme text.

- targets are sanitized;
- links may span adjacent cells;
- diff opens/closes links at run boundaries;
- overwriting removes the link;
- continuation inherits leader link identity;
- unsupported terminals render plain styled text.

## Selection metadata

Selection SHOULD be frame-local/effective metadata separate from document content. Selection changes dirty only affected regions. Copy reads leading graphemes and skips continuation/image-placeholder cells.

## Image placeholder cells

Protocol images use `CellKind.imagePlaceholder`.

- placeholders emit safe blanks where positioning/cleanup requires;
- ordinary text must not show through a visible protocol image;
- image identity/bytes live in overlay metadata, not every cell;
- moving/removing damages old and new rectangles;
- continuation and image-placeholder kinds cannot overlap;
- scroll acceleration is rejected when native-image semantics cannot be preserved.

Unicode fallback images use ordinary grapheme cells.

## Buffer representation and ownership

A buffer SHOULD use flat reusable storage: `index = y * width + x`. Stable mutable cell objects are allowed, but equality is value-based. A buffer owns cells, damage/span metadata, optional row hashes, and frame-local image placements. Compatibility row views are fixed length.

## Front/back synchronization

The front buffer is the immutable logical baseline after successful presentation. The back buffer is writable. Partial paint may copy unchanged values from front without marking damage; later paint creates damage.

After success ownership swaps. After failure the front remains authoritative and back is discarded/resynchronized.

## Resize

Dimension changes invalidate buffers/caches dependent on old size. The next frame is full damage. Old row/cell references must not be used.

## Required tests

Cover ASCII, CJK, ZWJ, flags/modifiers, combining marks, ambiguous-width profiles, wide glyph at right edge, leading/continuation overwrite, narrow↔wide transitions, clipping, selection/copy, hyperlinks, image overlap/cleanup, front/back reuse, resize, and randomized writes against a reference buffer.
