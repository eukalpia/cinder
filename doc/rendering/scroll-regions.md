# Terminal scroll regions

Status: **normative**.

Hardware scroll acceleration uses terminal scroll regions to move already committed rows
without repainting every shifted cell. It is an optimization only; rejection MUST preserve
correctness through ordinary damage and diff.

## Request model

A viewport submits a `TerminalScrollRequest` containing root-space integer bounds and an
integer line delta. Positive lines move content up; negative lines move content down.

The request is advisory. The terminal binding validates it after paint/composition information
for the frame is available.

## Acceptance requirements

A request may be accepted only when all are true:

- vertical movement is an integer number of rows;
- delta is non-zero and smaller than region height;
- region is within terminal bounds;
- region is full terminal width, unless a terminal capability explicitly supports safe
  horizontal margins and Cinder models them;
- no active incompatible image region intersects it;
- no overlapping accepted request creates ambiguous order;
- moved front-buffer rows and terminal rows will undergo the same mutation;
- newly exposed rows are included in damage;
- synchronized output or equivalent atomic presentation is available/preferred.

Partial-width regions are rejected by default.

## Validation and ordering

Requests are normalized and sorted deterministically. Overlapping requests are either merged
when semantically equivalent or all conflicting requests are rejected. Acceptance decisions
MUST NOT depend on hash-map iteration order.

Accepted commands are emitted before ordinary diff. The committed front-buffer model is
mutated with the same row copy/clear operation before cell comparison.

## Front-buffer mutation

For a region `[top, bottom)` and positive `lines`:

- source rows `[top + lines, bottom)` move to `[top, bottom - lines)`;
- newly exposed rows `[bottom - lines, bottom)` become empty/default in the front model;
- row hashes and image/hyperlink/selection metadata move identically;
- newly exposed rows are damaged.

Negative movement is symmetric.

Wide glyphs cannot cross row boundaries, so row movement preserves their ownership. Image
metadata moves only when the active protocol is declared scroll-safe.

## Fallback

A rejected request does not mutate the front model and emits no scroll command. The viewport's
ordinary paint/composition damage is diffed normally. Rejection is never a rendering error.

## Terminal state restoration

DECSTBM margins and any origin mode used for scrolling MUST be restored within the same frame
batch before normal cursor-addressed diff outside the region. The diff encoder must know the
post-scroll cursor position and style state.

## Multiple viewports

Multiple non-overlapping full-width requests MAY be accepted. Their command order and model
mutations must be identical. Nested or overlapping regions default to rejection unless a
formal composition rule proves equivalence.

## Exceptions

If scroll command generation or model mutation fails, the frame is aborted, the old front
buffer remains committed, and the next frame forces a safe full repaint. The renderer MUST
not continue with a terminal model that may differ from the actual terminal.

## Metrics

Record requests, accepted/rejected counts, rejection reason, shifted rows, avoided compared
cells, emitted scroll bytes, image conflicts, and fallback repaint cells.
