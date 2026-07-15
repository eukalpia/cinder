# Terminal diff

Status: **normative**.

Terminal diff converts the committed front framebuffer and the composed back framebuffer
into the smallest safe terminal command stream allowed by the cost model.

## Inputs

The diff stage receives:

- immutable front buffer and metadata planes;
- immutable composed back buffer and metadata planes;
- normalized root damage regions and row spans;
- front/back row hashes;
- accepted terminal scroll mutations;
- terminal capability and cost profile;
- desired final cursor/IME state.

It MUST NOT receive unresolved layer transparency or half-owned wide glyphs.

## Candidate rows

Only rows intersecting damage, image lifecycle operations, accepted scroll exposure, or
terminal desynchronization are candidates. Matching row hashes skip cell comparison.

For a hash mismatch, comparison begins at the candidate span expanded for:

- old and new wide-grapheme ownership;
- OSC 8 hyperlink run boundaries;
- style-state reconstruction when entering a span;
- image placeholder ownership;
- trailing-cell erase requirements.

The diff MUST compare canonical logical cells and metadata, not object identity.

## Runs

Changed cells are grouped into maximal safe runs. A run may include small unchanged gaps
when the terminal cost profile says this is cheaper than another cursor move and state setup.

A run boundary is mandatory at:

- row end;
- clip or damage safety boundary;
- incompatible image operation;
- hyperlink transition that cannot be represented inline;
- wide-grapheme ownership boundary;
- terminal command that resets cursor or style state unpredictably.

## Cursor movement

The encoder tracks its logical cursor. It chooses absolute or relative movement using the
terminal profile. It MUST never assume the cursor advanced by the UTF-8 byte length; advance
uses terminal-cell width.

A width-2 grapheme advances two columns. A continuation cell emits no bytes and is skipped by
the encoder.

## Style state

The encoder tracks resolved foreground, background, and text attributes. It emits only
required transitions, but MUST treat terminal commands with implicit resets according to the
capability profile.

At frame end, style state MAY remain active inside synchronized output only when the final
cursor/IME sequence is unaffected and the next frame's encoder starts from the known state.
The default safe policy resets style and closes hyperlinks before synchronized-output end.

## Erasing old content

When the back frame removes text, the diff emits explicit spaces or an erase command only
when the terminal profile proves equivalent background/style semantics. Clearing either half
of an old wide glyph clears both cells.

Trailing row content MAY use `EL` only when every cleared cell resolves to the same terminal
default background and contains no hyperlink/image metadata.

## Hyperlinks

OSC 8 state is opened for maximal contiguous hyperlink runs and closed before leaving the
run. Hyperlink state MUST be closed before image commands, row changes that use absolute
cursor movement, synchronized-output end, or exception recovery.

## Images

Text diff does not emit image placeholder cells. Image create/update/delete commands are
ordered relative to text so overlap produces the back framebuffer's ownership. Protocol
rules are in [images.md](images.md).

## Hardware scroll mutations

Accepted DECSTBM + `S`/`T` mutations are emitted before ordinary row diff. The front-buffer
model is mutated identically before comparison. Newly exposed rows remain damaged.

If the encoder cannot prove the scroll operation and model mutation are equivalent, it
rejects acceleration and performs ordinary diff.

## Synchronized output

A visual batch SHOULD be wrapped in DEC private mode 2026 when supported or safely ignored:

```text
CSI ? 2026 h
...complete frame commands...
CSI ? 2026 l
```

The opening and closing sequences are part of the same backend write as the frame.

## One write

The encoder accumulates all output in one reusable byte/string builder. A non-empty committed
frame invokes the backend visual write exactly once. A no-op frame invokes it zero times.

The following are forbidden inside a visual frame:

- direct `stdout.write` from widgets/render objects;
- intermediate `flush` calls;
- image helpers that bypass the batch;
- clipboard/title/capability commands interleaved without serialization.

## Commit and failure

The front buffer is replaced only after the backend accepts the full batch. If encoding
throws, the batch is discarded. If backend write throws or is partial:

- front buffer remains unchanged;
- terminal state becomes `desynchronized`;
- next successful frame begins with a safe reset/clear and full-frame output;
- image protocol resources are reconciled from the last known committed registry;
- diagnostics record byte count, last completed command boundary, and frame ID.

## Verification mode

Debug/CI verification MAY replay the emitted command stream into a terminal-state emulator
and assert that it equals the back framebuffer. Unicode, wide clearing, hyperlinks, scroll
regions, styles, and images MUST have emulator coverage.

## Metrics

Each frame records:

- candidate rows;
- row hash checks/hits;
- compared cells;
- changed cells;
- emitted graphemes/cells;
- cursor moves;
- style transitions;
- hyperlink transitions;
- image commands;
- scroll commands;
- ANSI/UTF-8 byte count;
- backend write count and duration.
