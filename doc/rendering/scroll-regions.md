# Hardware terminal scroll regions

Hardware scroll accelerates full-width vertical viewports by moving terminal rows instead of repainting them. It is optional; ordinary damage rendering is always the correctness fallback.

## Commands and request

Cinder may use DECSTBM and CSI `S`/`T`.

```dart
final class TerminalScrollRequest {
  int left;
  int top;
  int width;
  int height;
  int lines; // positive = content moves up
}
```

The request describes screen-cell geometry after layout and before diff.

## Eligibility

Accept only when:

- optimization enabled;
- valid previous/front buffer;
- clipped positive region;
- non-zero integer delta smaller than region height;
- entire terminal width covered;
- no incompatible native image;
- no conflicting fixed overlay/layer semantics;
- no ambiguous overlapping request;
- capability profile supports it;
- cursor/margins can be restored;
- byte-cost estimate beats ordinary diff.

Any failed condition rejects without error.

## Frame ordering

```text
begin synchronized output
set margins
move cursor
scroll S/T
reset margins
mutate baseline model identically
diff exposed/changed cells
images/cursor
end synchronized output
```

The stable implementation SHOULD mutate a provisional baseline or support rollback/unknown-baseline recovery on failure. Current Cinder mutates the previous model before diff, so transaction handling is a 1.0 task.

## Buffer semantics

Positive `lines`: rows `[top + lines, bottom)` move upward and bottom rows become blank/exposed. Negative values move rows downward and expose top rows. Styles, graphemes, continuations, and Unicode fallback image cells move as complete values. Exposed rows are damaged.

## Wide cells

Complete rows move, so valid wide pairs remain intact. Debug validates row invariants before/after.

## Images

Native images conservatively block scroll unless exact tested behavior is modeled. Unicode fallback moves as cells. Future native support must define whether terminal moves, clips, fixes, or deletes placements and update model identically.

## Multiple requests

Initial 1.0 policy SHOULD accept at most one full-width request per frame. Advanced support may accept non-overlapping regions deterministically. Overlap/nesting is coalesced or rejected. Rejected requests leave baseline unchanged and use normal diff.

## Overlays

Fixed headers/footers outside region are safe. Intersecting overlays are safe only if they move with cells or are repainted afterward. Selection, hover, cursor, and search highlights may require repaint.

## Resize/first frame

Disable for first frame, post-resize frame, unknown baseline, and full-redraw recovery.

## Cost model

```text
hardwareCost = margins + cursor + scroll command + reset + exposed-row paint
normalCost   = estimated changed-row diff bytes
```

Use hardware only with a benchmark-derived advantage. Current implementation has eligibility checks but not complete byte-cost gating.

## Failure behavior

Before output, discard request and use normal diff. If scroll bytes may be partially delivered, baseline becomes unknown, normal swap is not committed, margins are reset, and full recovery/redraw is scheduled. Cleanup always resets margins.

## Metrics

```text
scrollRequests
scrollRequestsAccepted
scrollRequestsRejected
scrollRowsMoved
scrollExposedRows
scrollBytes
scrollFallbackReason
```

Reasons: `disabled`, `noBaseline`, `notFullWidth`, `invalidDelta`, `imageIntersection`, `overlayConflict`, `capability`, `multipleConflict`, `cost`.

## Required tests

Cover up/down, delta boundaries, clipping, full-width requirement, image rejection, wide rows, overlay repaint, multiple-request policy, resize/first-frame rejection, exact escapes/reset, backend failure, and reference row movement.
