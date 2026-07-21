# 1.0.0-dev.3

- Added synchronized audio and video playback primitives with FFmpeg, FFprobe, and FFplay integration.
- Added media clocks, seeking, pause, volume, playback speed, late-frame dropping, and terminal video rendering.
- Added spreadsheet-style `DataGrid`, `Sparkline`, `BarChart`, and `LineChart` widgets.
- Added the publishable `cinder_cli` package with `cinder create`, `cinder doctor`, and `cinder version` commands.
- Added media-controller, data-widget, and project-scaffolding tests.
- Expanded pub.dev metadata for desktop platforms, documentation, issue tracking, and package topics.

---

# 1.0.0-dev.2

- Renderer V2 cached repaint layers and damage-only partial painting.
- Safe terminal scroll-region acceleration for vertical viewports.
- Flutter-style core icon API plus complete Material and Lucide catalogs.
- Protocol-aware Kitty, iTerm2, Sixel, and Unicode image rendering.
- Renderer, icon, image, documentation, and benchmark coverage.


---

# 0.8.0

## Bug Fixes
- **IME composition (Windows/CJK)**: Emit each rendered frame in a single pipe write so the terminal never anchors the IME composition window to a transient streaming cell — fixes IME window flickering across the screen during chat/log streaming
- **IME cursor**: Stabilize IME cursor position to prevent Chinese input flickering
- **TextField cursor**: Correct cursor position with multiple consecutive newlines
- **Windows input**: Restore `ENABLE_PROCESSED_INPUT` so Ctrl+C generates SIGINT
- **Windows input**: Cap the input loop wait so timers and signals fire reliably
- **Win32 input**: Encode `KEY_EVENT_RECORD.uChar` as UTF-8 for correct IME input
- **Win32 mouse**: Forward bare mouse motion as SGR button 35 so hover works
- **Character width**: Keep East Asian Ambiguous punctuation single-width
- **Selection**: Edge auto-scroll during selection drag in scroll views
- **Terminal shutdown**: Stop sending DECRDA query on TUI shutdown
- **Project paths**: Terminate `getProjectDirectory` walk at Windows drive roots
- **TextField**: Use `InputDecoration` instead of `BoxDecoration`

## Refactoring
- **Character width**: Delegate CJK classification to the xterm wcwidth table

## Chores
- **CI**: Bump GitHub Actions to node24-compatible majors
- Strengthen the test suite with additional matchers, audit fixes, and gap coverage

---

# 0.7.0

## Layout pipeline

The layout-skip check now uses value equality on constraints instead of
`identical()`, and every core mutation path marks layout explicitly. Apps
get strictly fewer redundant relayouts than 0.6.0 (which effectively
re-laid out the full tree every frame), while content updates render
reliably.

## Bug Fixes
- **Overlay/Stack positioning**: Mark parent dirty when applying Positioned parent data, including the copy-in-place path used inside Overlay/Navigator (fixes overlay children frozen at stale positions)
- **Padding/Align**: Convert RenderPadding and RenderPositionedBox to compare-and-mark setters so padding/alignment changes re-layout (fixes stale layout when constraints are unchanged)
- **Child reorder**: Mark layout when moving render children, so reordering const/keyed children in Row/Column/Stack takes effect
- **ListView/LayoutBuilder**: Always mark layout in update() — a stable (hoisted) builder reading mutated state now re-renders instead of pinning stale content
- **ListView**: Evict stale separator cache entries when itemCount shrinks
- **Element slots**: Propagate slot changes for identity-equal components, so reordering const children updates paint order
- **Ticker**: Skip tail reschedule when onTick stops and restarts the ticker (fixes orphaned frame callbacks with AnimationController status listeners)
- **Selection**: Notify listeners on selection drag state mutations so list viewports repaint selection bands

## New APIs
- **EdgeInsets**: Value equality (`==`/`hashCode`), matching Flutter semantics

## Performance
