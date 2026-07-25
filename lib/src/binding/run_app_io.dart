import 'dart:async';
import 'dart:io';

import 'package:cinder/cinder.dart'
    hide StdioBackend, SocketBackend, WebBackend;
import 'package:cinder/src/backend/socket_backend.dart';
import 'package:cinder/src/backend/stdio_backend.dart';
import 'package:cinder/src/backend/terminal.dart' as term;

(File?, bool) _useShellMode() {
// Check for shell mode
  final shellHandleFile = File(getShellHandlePath());
  if (shellHandleFile.existsSync() case false) {
    return (null, false);
  }

  final socketPath = shellHandleFile.readAsStringSync().trim();
  if (socketPath.isEmpty) {
    return (null, false);
  }

  if (File(socketPath).existsSync()) {
    return (shellHandleFile, true);
  }

  return (null, false);
}

/// Run a TUI application on native platforms (Linux, macOS, Windows).
Future<void> runAppImpl(
  Widget app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
}) async {
  // Wrap the user's app with DebugOverlay so Ctrl+G toggle works out of the box
  final wrappedApp = DebugOverlay(child: app);

  // Determine backend and whether we're in shell mode
  final TerminalBackend effectiveBackend;
  final bool isShellMode;

  if (backend != null) {
    effectiveBackend = backend;
    isShellMode = false;
  } else if (_useShellMode() case (final file?, true)) {
    final socketPath = await file.readAsString();
    final socket = await Socket.connect(
      InternetAddress(socketPath.trim(), type: InternetAddressType.unix),
      0,
    );
    effectiveBackend = SocketBackend(socket);
    isShellMode = true;
  } else {
    effectiveBackend = StdioBackend();
    isShellMode = false;
  }

  await _runApp(wrappedApp, effectiveBackend, enableHotReload, isShellMode);
}

Future<void> _runApp(
  Widget app,
  TerminalBackend backend,
  bool enableHotReload,
  bool isShellMode,
) async {
  TerminalBinding? binding;
  LogServer? logServer;
  Logger? logger;

  try {
    logServer = LogServer();
    try {
      await logServer.start();
      logger = Logger(logServer: logServer);
    } catch (e) {
      stderr.writeln('Failed to start log server: $e');
    }

    await runZoned(() async {
      final terminal = term.Terminal(backend);
      final usesNativeStdio = backend is StdioBackend;
      final capabilities = TerminalCapabilities.fromEnvironment(
        Platform.environment,
        stdinHasTerminal: isShellMode || !usesNativeStdio || stdin.hasTerminal,
        stdoutHasTerminal:
            isShellMode || !usesNativeStdio || stdout.hasTerminal,
      );
      binding = TerminalBinding(terminal, capabilities: capabilities);

      binding!.initialize();
      binding!.attachRootWidget(app);

      if (enableHotReload && !bool.fromEnvironment('dart.vm.product')) {
        await binding!.initializeHotReload();
      }

      await binding!.runEventLoop();
    },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String message) {
            logger?.log(message);
            if (isShellMode) {
              parent.print(zone, message);
            }
          },
          handleUncaughtError: (Zone self, ZoneDelegate parent, Zone zone,
              Object error, StackTrace stackTrace) {
            final errorMessage = 'ERROR: $error\n$stackTrace';
            logger?.log(errorMessage);
            if (isShellMode) {
              stderr.writeln(errorMessage);
            }
          },
        ));
  } catch (e) {
    if (isShellMode) {
      stderr.writeln('Shell mode error: $e');
    }
  } finally {
    if (binding != null && !binding!.shouldExit) {
      binding!.shutdown();
    }
    try {
      await logger?.close();
      await logServer?.close();
    } catch (_) {}
  }
}
