# cinder CLI

CLI tools for cinder - A Terminal User Interface framework for Dart.

## Installation

Install the CLI globally from a repository checkout:

```bash
cd packages/cinder_cli
dart pub global activate . --source path
```

## Commands

### `cinder shell`

Start a cinder shell server that cinder apps can render into. This allows running cinder apps from IDEs with debugger support.

### `cinder logs`

Stream logs from a running Cinder app via WebSocket. Logs are displayed until you press Ctrl+C or the app exits. Use `cinder logs --mode get` to fetch buffered logs, or `--pid <pid>` to select an instance.

### `cinder run dart <script.dart> [arguments]`

Run a Dart script with VM service support for debugging and profiling. Arguments after `dart` are forwarded to Dart and the script.

## Shell workflow

The shell requires macOS or Linux. Start it from the same Dart project as the app.

**How it works:**

1. The shell creates a Unix domain socket at `~/.cinder/<project-hash>/shell.sock`
2. It writes the socket path to `~/.cinder/<project-hash>/shell_handle`
3. When you run a cinder app (via `dart run`), it automatically detects the shell_handle file
4. The app connects to the shell and renders frames over the socket
5. The shell displays the frames in its terminal
6. Input from the shell terminal is forwarded to the app

**Usage:**

Terminal 1 - Start the shell:

```bash
cinder shell
```

Terminal 2 - Run your cinder app (or from IDE with debugger):

```bash
# From the repository root:
dart run example/example.dart
```

The app will automatically render into the shell instead of its own stdout.

**Benefits:**

- ✅ Run cinder apps from IDEs (VSCode, IntelliJ, etc.)
- ✅ Attach debugger to cinder apps
- ✅ Set breakpoints and inspect state
- ✅ No changes needed to app code - works automatically
- ✅ Falls back to normal rendering if shell is not running
- ✅ `print()` statements appear in your IDE/terminal AND in logs
- ✅ Debug output is visible while TUI renders in the shell

## Development Workflow

### Normal Mode (Direct Rendering)

```bash
# Run app directly - renders to its own terminal
# print() statements stream to WebSocket logs
dart run bin/my_app.dart

# In another terminal, view logs:
cinder logs
```

### Shell Mode (IDE Debugging)

```bash
# Terminal 1: Start shell
cinder shell

# IDE or Terminal 2: Run app with debugger
# App automatically detects shell and renders there
# print() statements appear in your IDE/terminal AND in logs!
dart run bin/my_app.dart

# Optional Terminal 3: View logs
cinder logs
```

**Note:** In shell mode, `print()` statements appear in BOTH the terminal/IDE where you run the app (Terminal 2 above) AND are streamed to WebSocket logs (viewable with `cinder logs`), while the TUI renders in the shell (Terminal 1). This gives you maximum flexibility for debugging!

## Technical Details

### Communication Protocol

The shell and app communicate via Unix domain sockets with a simple pass-through architecture:

**App → Shell:** Raw ANSI terminal output (escape sequences, colors, text)
**Shell → App:** Raw stdin input (keyboard, mouse events)

The app uses a `SocketTerminal` instead of the regular `Terminal`, which writes all output to the socket instead of stdout. The shell simply forwards this output to its stdout and forwards its stdin back to the app. This means the protocol is just raw terminal data - no custom serialization needed!

## Examples

Run a Dart example from the repository’s `example/` directory in either normal or shell mode.

## Troubleshooting

**App doesn't connect to shell:**

- Make sure the shell is running first
- Check for `shell_handle` beside the socket path printed by the shell; discovery uses `~/.cinder/<project-hash>/`
- Verify the socket path in shell_handle is correct

**Shell shows garbled output:**

- This shouldn't happen, but if it does, check for protocol version mismatches
- Try recompiling both the CLI and the app

**Input not working:**

- Make sure your terminal supports raw mode
- Check that stdin is not being piped or redirected
