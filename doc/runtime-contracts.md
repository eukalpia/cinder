# Runtime contracts

This document defines the behavior applications may rely on when building on
Cinder. These contracts are release gates for the 1.0 line and should change
only through an explicit compatibility decision.

## Frame pipeline

A scheduled frame progresses through the following phases:

1. transient callbacks;
2. mid-frame microtasks;
3. persistent build, layout, paint, and terminal composition;
4. post-frame callbacks.

Repeated requests before a frame begins are coalesced. Render objects should
invalidate the narrowest correct phase: build for configuration changes, layout
for geometry changes, and paint for visual-only changes.

The renderer maintains reusable front and back buffers. Dirty spans bound the
cells considered by differential output. A frame that produces no visual change
must not emit cursor movement, style changes, or cell data.

Applications can inspect frame timing through `SchedulerBinding` and configure
standard diagnostics at the application root:

```dart
CinderApp(
  debug: const CinderDebugOptions(
    showPerformanceOverlay: true,
    showRepaintRegions: true,
    showFrameTimings: true,
    detectLayoutThrashing: true,
  ),
  home: const DashboardScreen(),
);
```

Diagnostics are disabled by default and must not change production rendering
semantics.

## Text and columns

All layout, cursor, selection, clipping, and truncation logic is expressed in
terminal columns rather than UTF-16 code units or Unicode scalar values.

A user-visible character is processed as a grapheme cluster. Wide graphemes
occupy two cells and are never split at a clipping boundary. Combining marks,
variation selectors, and zero-width joiners remain attached to their base
cluster.

Use `TerminalText.measure`, `TerminalText.truncate`, and
`TerminalText.sliceColumns` instead of `String.length` or `substring` for
terminal geometry.

## Trust boundary

Framework-generated terminal control is trusted. File contents, logs, process
output, remote data, Markdown, source code, and model output are untrusted text.

Render untrusted content through `TerminalText.safe`. Direct terminal APIs also
sanitize window and icon metadata so nested OSC, CSI, or DCS sequences cannot be
injected accidentally.

See [security.md](security.md) for the threat model and testing requirements.

## Input model

Cinder distinguishes normalized input categories:

- `KeyboardInputEvent` for logical key actions and modifiers;
- `TextInputEvent` for committed text independent of a physical key;
- `PasteInputEvent` for bracketed or synthetic paste;
- `MouseInputEvent` for button, motion, and wheel input;
- `ResizeInputEvent` for viewport changes;
- `TerminalFocusInputEvent` for terminal focus changes.

Focus is owned by `FocusManager`, `FocusScopeNode`, and `FocusNode`. Keyboard
handlers run against the primary focus path. Traversal must use attached,
focusable nodes and remain deterministic after rebuilds and route changes.

Terminal features are conditional. Applications must read
`TerminalCapabilities` and provide fallbacks instead of assuming true color,
mouse tracking, graphics protocols, hyperlinks, clipboard access, or enhanced
keyboard protocols.

## Asynchronous lifecycle

Every long-running operation must have an owner. Use `CinderTaskScope` for
cooperative cancellation and `CinderResourceScope` for deterministic release of
timers, streams, processes, file watchers, sockets, and remote channels.

Disposal follows these rules:

1. no new work can be registered after disposal begins;
2. cancellation is idempotent;
3. cleanup runs in reverse registration order;
4. one cleanup failure does not prevent later resources from being released;
5. task disposal waits for cooperative cleanup paths to finish;
6. terminal restoration is attempted even after an application error.

Operations that ignore their cancellation token are application defects. A
scope cannot safely force an arbitrary Dart future to stop.


## Non-interactive output

Applications may render a Widget tree through `renderPlainWidget` without
entering raw mode or the alternate screen. The result contains the terminal
buffer, trimmed text lines, and a JSON representation. This path must not write
ANSI control sequences or mutate the user's physical terminal.

Semantic output is independent from visual output. `SemanticsSnapshot` exports
roles, labels, values, and state as plain text or JSON even when the interactive
visual layout uses borders, color, or chart glyphs.

## Capability degradation

The minimum supported environment is a basic terminal capable of displaying
plain text. Optional behavior degrades as follows:

| Capability | Preferred behavior | Fallback |
| --- | --- | --- |
| True color | 24-bit RGB | 256/16-color quantization |
| Native image | Kitty, iTerm2, or Sixel | Unicode blocks or text placeholder |
| Enhanced keyboard | Kitty keyboard protocol | standard terminal sequences |
| Mouse | pointer and wheel events | keyboard-only operation |
| OSC 8 links | clickable hyperlink | visible URL/text |
| OSC 52 clipboard | terminal clipboard integration | application-managed copy |
| Synchronized output | atomic frame presentation | buffered differential output |

`TERM=dumb` disables optional interactive assumptions. SSH and tmux are tracked
as transport/session properties rather than treated as proof of a feature.

## 1.0 release gates

A stable release requires:

- analyzer and test suites green on supported Dart versions;
- deterministic terminal restoration after normal exit, signals, and errors;
- Unicode regression coverage for combining, CJK, emoji, and ZWJ sequences;
- sanitizer regression coverage for CSI, OSC, DCS, C1, and bidi controls;
- resize, focus, mouse, paste, and keyboard integration coverage;
- renderer benchmarks with explicit regression thresholds;
- verified behavior on Windows Terminal, macOS terminals, Linux terminals, SSH,
  and tmux;
- no hidden global background work after root disposal;
- one production-scale reference application exercising the complete stack.

Examples demonstrate APIs. The reference application validates that the APIs
remain coherent under real workload, failure, resize, and shutdown conditions.
