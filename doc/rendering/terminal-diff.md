# Terminal diff and presentation

The terminal diff turns a composed logical frame into the smallest safe terminal command payload.

## Baseline

The front buffer represents the last successfully presented physical state. The diff MUST compare against that baseline, never an unpresented buffer, failed frame, layer cache, or widget state.

After resize, output failure, unknown external terminal mutation, or baseline invariant failure, the baseline is unknown and the next frame is full redraw.

## Inputs

The diff receives current composed buffer, previous/front buffer, conservative damage, terminal capability profile, current/previous image placements, accepted hardware-scroll operations, and desired final cursor/IME state. Buffers must have equal dimensions for differential output.

## Output order

The frame builder appends:

1. begin synchronized output when supported;
2. approved hardware scroll;
3. image cleanup that must precede replacement;
4. cell runs/full redraw;
5. image placements;
6. final style/link reset;
7. reset scroll region;
8. final cursor position/visibility;
9. end synchronized output.

This order prevents cursor/image/IME intermediate artifacts.

## Cell equality

Equality includes grapheme, foreground/background, attributes, width/kind, hyperlink, effective presentation metadata, and placeholder semantics. Identity is irrelevant. Continuations participate in clearing/damage but are never emitted independently.

## Wide-character transitions

Required correctness:

- wide → same wide: no output;
- wide → narrow: clear/rewrite both old columns as needed;
- narrow pair → wide: emit one leader and count two written cells;
- writing at old continuation clears old leader+continuation;
- run boundaries never split width-2 graphemes;
- removed continuations never leave stale columns.

## Damage restriction and row hashes

Scan only conservative damaged spans expanded by old/new wide pairs. Row hashes MAY reject unchanged damaged rows, with debug/reference verification. Current+previous damage union detects removals.

## Run generation

A run is one cursor-positioned sequence of adjacent output cells. The encoder starts on a non-continuation, opens style/link state, writes graphemes/placeholders, bridges unchanged gaps only when cheaper, closes/reset state, and reports written cells/bytes. Image placeholders may force separation.

## Cost model

Estimate sparse runs, whole-row rewrite, and full redraw by actual encoded bytes:

```text
sparseRunCost = Σ(cursorMove + style/link setup + encoded run + resets)
wholeRowCost  = cursorMove + setup + encoded row + resets
fullRedrawCost = clear/home + encoded screen + images + cursor
```

Choose the cheapest safe path. A fixed small-gap fast path is allowed; current Cinder bridges up to four unchanged cells.

## Style encoding

State includes foreground, background, bold/dim, italic, underline, strike-through, reverse, and hyperlink. Transitions are minimal but correctness-first, unsupported attributes degrade consistently, color quantization follows capability profile, and no run leaks style/link state.

## Full redraw

A full redraw clears artifacts, homes cursor, writes every row, skips continuations, writes safe blanks for image placeholders, re-emits visible protocol images, and restores final cursor state. It is mandatory for first frame and size mismatch.

## Images

Stale image regions are deleted/cleared before conflict, unchanged placements need not re-emit, full clear requires re-emission, and active image state commits only after successful presentation.

## Synchronized output

DEC private mode 2026 wraps the complete frame when supported. Unsupported terminals ignore it; logical atomicity still requires buffering the whole payload and presenting once.

## Single batched stdout write

Stable API:

```dart
final payload = FrameOutputBuilder()..append(...);
await backend.present(payload.takeBytes());
```

The renderer MUST call `present` exactly once per frame. The backend may internally drain partial OS writes, but no component may interleave stdout bytes.

Current Cinder performs many `terminal.write` appends followed by one synchronized flush. This is one logical flush, but an explicit single-payload `present` API remains a 1.0 task.

## Commit protocol

```text
compose provisional frame
encode payload
backend.present(payload)
  success → swap buffers, commit images, clear damage
  failure → preserve front baseline, discard provisional commit
```

If partial delivery is uncertain, mark physical baseline unknown and recover with reset/full redraw.

## Metrics

```text
comparedCells
writtenCells
ansiRuns
outputBytes
cursorMoves
styleTransitions
linkTransitions
rowRewrites
sparseRuns
fullRedraw
encodeTime
presentTime
```

Metrics use actual backend bytes, not UTF-16 code units.

## Security

Untrusted text never contains raw terminal commands. ANSI/OSC/DCS/APC/Kitty/Sixel/cursor output comes only from trusted encoders. Hyperlinks/images use sanitized metadata channels.

## Exception behavior

Dimension mismatch chooses full redraw/abort; encoding invariant failure aborts provisional frame; image failure safely falls back/omits; backend failure prevents commit and starts recovery; final cursor failure counts as frame failure when reported.

## Required tests

Cover sparse changes, whole-row threshold, first frame/resize, styles/links, every wide transition, image boundaries, scroll+diff, exactly one `present`, partial writes, injected output failures, and randomized buffers against a reference encoder.
