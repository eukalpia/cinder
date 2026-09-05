# Bubble Tea comparison adapter

Build with `go build -o /tmp/bubbletea-bench .`, then run
`/tmp/bubbletea-bench workload.json` inside the comparison driver's PTY.
The JSON contains `width`, `height`, `fps`, and two distinct `frames` of
printable ASCII text with newline-separated rows. The first frame appears at
startup; each `n` switches frames, and `q` exits cleanly.

This uses Bubble Tea 2.0.9's normal stdin/stdout terminal backend, alternate
screen, `WithFPS`, `WithWindowSize`, and a truecolor profile. The driver must
set the actual PTY dimensions: a real terminal's size overrides
`WithWindowSize`. Bubble Tea supports at most 120 FPS; the primary comparison
uses 60 FPS. Frames are precomputed, and the app adds no timers, clocks,
measurement output, or rendering shortcuts.

Bubble Tea queries synchronized output with `ESC[?2026$p` when its terminal
environment supports capability probing. With `TERM=xterm-256color`, omit
inherited `TERM_PROGRAM` and `SSH_TTY` to use that default probing path. The
driver can answer `ESC[?2026;2$y` to advertise support in the reset state;
subsequent rendered updates contain `ESC[?2026h` and `ESC[?2026l`. Without the
reply, those markers are absent. It also queries Unicode mode 2027; an
unsupported-mode reply is `ESC[?2027;0$y`. Startup and capability negotiation
belong outside the measured interval.
