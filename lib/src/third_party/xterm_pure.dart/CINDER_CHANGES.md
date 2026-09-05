# Cinder changes to bundled xterm

The original MIT copyright and permission notice remain in `LICENSE` beside
these sources. Cinder modifications are attributed in the repository `NOTICE.md`.

## Resource policy and compatibility

Cinder ignores child-requested window resizing (`CSI 8;rows;columns t`) in the
bundled emulator. The application owns its viewport; direct `Terminal.resize`
calls still resize the screen and notify `onResize`. Terminal size queries report
those host-provided dimensions. This policy also applies when the bundled
`Terminal` is used directly, not just inside `TerminalXterm`.

Each REP command repeats at most `viewWidth * viewHeight` characters. Larger
requests truncate at this budget; they do not generate arbitrarily large
scrollback or hold the UI isolate in an unbounded loop. Ordinary counts preserve
wrapping, scrolling margins, and wide characters. The budget counts repeated
characters, so a wide character may occupy two cells. The bound scales with the
viewport chosen by the trusted host, and has no additional configuration.

Numeric CSI parameters greater than 2147483647 discard the entire sequence
through its final byte. This prevents overflow from turning malformed digits
into a different valid parameter on native or web runtimes. These are deliberate
resource limits, not a claim of unrestricted xterm protocol compatibility.

## Incremental parsing

The escape parser consumes split CSI and OSC sequences incrementally instead of
retaining and reparsing their original input on every write. Both sequence types
have a fixed limit of 8192 encoded UTF-8 bytes, including the escape introducer
and final byte or terminator. This limit applies to `TerminalXterm` through the
bundled emulator and has no runtime configuration. On overflow, the parser
releases the accumulated payload and discards input until the CSI final byte,
OSC BEL, or OSC ST (`ESC` followed by `\`). Discarded payload never becomes
visible terminal text, and the completed oversized sequence is not dispatched.

Consumed input blocks are released before each parser write returns, including
the last exhausted block. Partial state retains only the bounded OSC strings or
CSI parameters. This bounds retained control payload, not the caller's current
input chunk or the emulator's rendered screen and scrollback.

The existing CSI and OSC handlers remain in place. Truncated extended-color SGR
parameters are ignored safely instead of indexing beyond the parameter list.
Normal split BEL/ST terminators, CSI, Unicode, charset changes, RGB/indexed
colors, and debugger token spans have focused regression coverage.

Synchronous writes from control callbacks queue behind already received input.
Completed dispatch state is released even if a callback throws, preserving
exception propagation and allowing later input to recover in order.
