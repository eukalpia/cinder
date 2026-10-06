import 'dart:async';

import 'package:cinder/cinder.dart'
    hide StdioBackend, SocketBackend, WebBackend;
import 'package:cinder/src/backend/web_backend.dart';
import 'package:cinder/src/backend/terminal.dart' as term;
import 'package:cinder/src/binding/development_features.dart';

/// Run a TUI application on web platform.
Future<void> runAppImpl(
  Widget app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
  bool? enableDebugOverlay,
  bool? enableLogServer,
}) async {
  // Browsers have no process environment, and there is no log server on web.
  final debugOverlay = resolveDevelopmentFeature(
    explicit: enableDebugOverlay,
    debugDefault: assertionsEnabled,
  );
  final wrappedApp = debugOverlay ? DebugOverlay(child: app) : app;

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
    debugOverlayShortcutEnabled: debugOverlay,
  );

  binding.initialize();
  binding.attachRootWidget(wrappedApp);

  // Hot reload not supported on web

  await binding.runEventLoop();
}
