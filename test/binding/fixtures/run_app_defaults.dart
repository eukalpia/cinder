import 'dart:io';

import 'package:cinder/cinder.dart';

/// Runs an application on pipes and reports its development tools on stderr.
///
/// Arguments `overlay=<bool>` and `logs=<bool>` are forwarded to [runApp].
/// Every exit request is reported and cancelled, so only a termination
/// request can end the process.
Future<void> main(List<String> arguments) async {
  bool? option(String name) {
    for (final argument in arguments) {
      if (argument == '$name=true') return true;
      if (argument == '$name=false') return false;
    }
    return null;
  }

  await runApp(
    const _ReportingApp(),
    enableHotReload: false,
    enableDebugOverlay: option('overlay'),
    enableLogServer: option('logs'),
  );
}

class _ReportingApp extends StatefulWidget {
  const _ReportingApp();

  @override
  State<_ReportingApp> createState() => _ReportingAppState();
}

class _ReportingAppState extends State<_ReportingApp> {
  @override
  void initState() {
    super.initState();
    final binding = TerminalBinding.instance;
    binding.addExitRequestHandler(() {
      stderr.writeln('exit-request');
      return AppExitResponse.cancel;
    });
    print('captured print output');
    final endpoint = File(getLogPortPath());
    final overlay = context.findAncestorWidgetOfExactType<DebugOverlay>();
    stderr
      ..writeln('overlay-shortcut=${binding.debugOverlayShortcutEnabled}')
      ..writeln('overlay-installed=${overlay != null}')
      ..writeln('log-endpoint=${endpoint.existsSync() ? endpoint.path : ''}')
      ..writeln('ready');
  }

  @override
  Widget build(BuildContext context) => const Text('fixture');
}
