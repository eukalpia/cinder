# Runtime stability

Cinder treats lifetime, input, Unicode geometry, terminal capabilities, and
shutdown as framework contracts. Applications should not need private terminal
heuristics or ad-hoc cleanup to remain safe during resize, failure, navigation,
or process exit.

## Structured lifetime

Every asynchronous operation has an owner. A `State` exposes `tasks` and
`resources`, plus convenience methods for common resource types:

```dart
class _LogsState extends State<Logs> {
  @override
  void initState() {
    super.initState();

    runTask((token) async {
      while (!token.isCancelled) {
        await readNextBatch(token);
      }
    }, label: 'log-stream');

    trackTimer(Timer.periodic(const Duration(seconds: 1), (_) => refresh()));
    trackSubscription(events.listen(onEvent));
  }
}
```

Unmounting the state synchronously prevents new work, requests cooperative task
cancellation, and begins deterministic resource release. Task diagnostics retain
a bounded history instead of retaining every completed future for the lifetime of
a long-running screen. Successful work remains distinct from cancelled work.

Operations must still cooperate with cancellation. The framework cannot safely
interrupt arbitrary Dart code that ignores its token.

## Normalized input pipeline

Raw terminal bytes are decoded into normalized events and routed in three
phases:

1. capture from the application root toward the target;
2. target dispatch;
3. bubble from the target back toward the root.

Handlers may ignore, handle, or stop propagation. Key events preserve down,
repeat, and up state. Bracketed paste, terminal focus, resize, mouse, committed
text, and IME composition use dedicated event types instead of pretending every
input is a physical key.

A single Escape byte is ambiguous because it may start CSI, SS3, Alt, mouse, or
keyboard-protocol input. `TerminalBinding` waits for a short ambiguity window and
emits Escape only when no continuation arrives. Incomplete input is bounded by a
hard parser limit so malformed streams cannot grow memory without bound.

## Unicode geometry

`TerminalText` maps between UTF-16 offsets used by Dart strings and terminal
columns used by layout and cursor movement:

```dart
final width = TerminalText.measure(value);
final column = TerminalText.columnForOffset(value, selection.extentOffset);
final offset = TerminalText.offsetForColumn(value, column);
final safeOffset = TerminalText.normalizeOffset(value, arbitraryOffset);
```

Mappings snap to grapheme boundaries and never split combining sequences, CJK
wide characters, emoji modifiers, or zero-width-joiner families. `TextField`
length limits count grapheme clusters rather than UTF-16 code units.

## Capability negotiation

`TerminalCapabilities` is an immutable session profile. Environment detection is
conservative and active terminal queries are opt-in. CI, redirected output, and
`TERM=dumb` disable raw mode, alternate screen, mouse, paste, focus reporting,
and enhanced keyboard protocols unless `CINDER_FORCE_INTERACTIVE` is explicitly
set for a controlled environment.

The profile records transport properties such as SSH, tmux, and screen without
treating them as proof that a downstream protocol is available. Applications
should branch on capabilities and provide text or keyboard-only fallbacks.

## Shutdown guarantee

Shutdown executes independent cleanup stages so one failure cannot suppress the
rest:

1. stop polling and input ambiguity timers;
2. cancel State-owned tasks and resources;
3. unmount the root tree;
4. disable enhanced keyboard, focus, paste, mouse, and synchronized output;
5. leave the alternate screen and restore raw terminal state;
6. close streams and the backend;
7. release the global binding instance.

The first cleanup error may still be surfaced, but terminal restoration and later
cleanup stages are always attempted. A completed shutdown permits a fresh binding
session in the same process, which is required by tests, embedded shells, and
restartable applications.

## Validation

The stabilization suite covers bounded task history, cancellation semantics,
split and malformed escape sequences, standalone Escape, Kitty key lifecycle,
terminal focus, Unicode offsets, capability profiles, non-interactive startup,
protocol restoration, and repeated binding sessions. The benchmark suite tracks
input parsing, Unicode geometry, capability negotiation, routing, and task
lifecycle overhead.
