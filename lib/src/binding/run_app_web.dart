import 'dart:async';

import 'package:cinder/cinder.dart'
    hide StdioBackend, SocketBackend, WebBackend;
import 'package:cinder/src/backend/web_backend.dart';
import 'package:cinder/src/backend/terminal.dart' as term;

/// Run a TUI application on web platform.
Future<void> runAppImpl(
  Widget app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
}) async {
  // Wrap the user's app with DebugOverlay so Ctrl+G toggle works out of the box
  final wrappedApp = DebugOverlay(child: app);

  final effectiveBackend = backend ?? WebBackend();
  final terminal = term.Terminal(effectiveBackend);
  // TerminalBinding is exported from package:cinder/cinder.dart
  final binding = TerminalBinding(
    terminal,
    capabilities: const TerminalCapabilities(
      isInteractive: true,
      supportsRawMode: true,
      supportsAlternateScreen: true,
      supportsMouse: true,
      supportsBracketedPaste: true,
      supportsFocusEvents: true,
      supportsTrueColor: true,
      supports256Colors: true,
    ),
  );

  binding.initialize();
  binding.attachRootWidget(wrappedApp);

  // Hot reload not supported on web
  // No log server on web

  await binding.runEventLoop();
}
