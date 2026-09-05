# workspace-v1 contract

`data_workload.py` writes the input JSON and implements the screen oracle. The
input has `kind: "workspace-v1"`, dimensions, FPS, `records`, and `actions`.
The default is 120 columns, 40 rows, 60 FPS, and 50,000 records. Minimum
dimensions are 100 × 12. Screens contain only printable ASCII and line breaks.

Record `i` has `id=i`, `service="service-" + (i % 17)` with a two-digit suffix,
`level=[INFO,WARN,ERROR,DEBUG][i % 4]`, `score=(i*37)%10000`, and a message
`"request " + six-digit i + " needle"` when `i % 97 == 0`, otherwise the suffix
is `" regular"`. Appending creates record `records.length` by the same rule.
All initial records are supplied in JSON; adapters must not substitute their
own data generator or precompute the action screens before input.

The Dart adapter decodes these fields once into immutable `WorkspaceRecord`
objects before readiness. Its matches retain references to those objects;
appending constructs one new typed record after the action arrives. This changes
the adapter's data representation, not the contract or framework core. Rebuilds
still perform the specified scan, lowercase search concatenation, filtering,
and sorting on each applicable action, without cached search/sort results.

Initial matches are in input order. Cursor, viewport top, and step are zero;
selection is empty, search is empty, the error filter is off, sort mode is
`id`, and the event log contains `ready`. Page size is `height - 8`.

| Key | Action |
| --- | --- |
| `j`, `k` | Move cursor down/up one matching record. |
| `p` | Advance cursor one page. |
| `g`, `G` | Move to first/last match. |
| `x` | Toggle the current record ID in the persistent selected-ID set. |
| `f` | Toggle search between the empty string and `needle`; rebuild matches. |
| `e` | Toggle the ERROR-only level filter; rebuild matches. |
| `s` | Toggle score sort: first press descending, then ascending; rebuild. |
| `a` | Append one record, then rebuild matches. |
| `q` | Exit successfully and restore terminal input modes. |

Search scans the lowercase concatenation of service, one space, level, one
space, and message, using a literal substring match. The error filter is
conjunctive. Rebuild scans all records. Score sorting uses record ID ascending
to break ties in either direction. Rebuild resets cursor and viewport top to
zero, retaining selection by ID. No record mutations other than append occur.

Every recognized action increments step. Clamp cursor to the match range, or
zero for no matches. If cursor is before top, set top to cursor. If cursor is
at/after `top + page_size`, set top to `cursor - page_size + 1`. Append a log
entry `six-digit step + action-name + cursor=... + matches=...`; retain the
last three entries. These changes occur after key delivery.

The 24-key cycle is `jpjxfspejxsfeGakgaxpksfg`. The driver repeats it across
warmup and measured updates without resetting the model. Use warmup and
measurement counts that are multiples of 24 for equal action mixes. Search,
filter, sort, and selection retain their current states across cycle boundaries;
appended data remains resident. Two cycles therefore do not imply the same
full model state, even when the visible cursor returns home.

Render exactly two status lines, the table heading, `height - 8` visible table
rows, `Event log`, exactly three log lines (blank-pad on the left until full),
and one key legend. Show the cursor as `>` and selection as `*` in the first
two columns of each row. Numeric IDs use six digits and scores four digits;
levels are padded to five characters. Each complete output line is clipped or
space-padded to the terminal width. Only the viewport rows are formatted.
`Workspace.lines()` defines the byte-for-byte text layout. The input file
contains no expected output grids; the driver alone derives them before
launching the adapter.
