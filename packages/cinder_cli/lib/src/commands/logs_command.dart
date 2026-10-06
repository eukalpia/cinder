import 'dart:convert';
import 'dart:io';

import 'package:cinder/cinder.dart';
import 'package:cinder_cli/src/deps/fs.dart';
import 'package:cinder_cli/utils/cli_command.dart';

/// Run the logs command to stream logs from a running cinder app
class LogsCommand extends CliCommand {
  LogsCommand() {
    argParser.addOption(
      'pid',
      abbr: 'p',
      help: 'Connect to a specific instance by PID',
    );
    argParser.addOption(
      'mode',
      abbr: 'm',
      help:
          'Output mode: "get" fetches buffered logs and exits, '
          '"listen" streams continuously (default)',
      allowed: ['get', 'listen'],
      defaultsTo: 'listen',
    );
  }

  @override
  String get description => '''
Stream logs from a running cinder app via WebSocket.

The app must have its log server enabled: debug builds (Dart assertions
enabled, e.g. `dart run --enable-asserts` or `cinder run`) start it
automatically; otherwise set CINDER_LOG_SERVER=1 or pass
`enableLogServer: true` to runApp.

Modes:
  listen  - Stream logs continuously in real-time (default). Press Ctrl+C to exit.
  get     - Fetch all buffered logs and exit immediately. Useful for scripts and CI.

Examples:
  cinder logs              # Stream logs continuously
  cinder logs --mode get   # Fetch current logs and exit
  cinder logs -m get       # Short form''';

  @override
  String get name => 'logs';

  /// Clean up a stale port file.
  Future<void> _cleanupStalePortFile(String path) async {
    try {
      await fs.file(path).delete();
    } catch (_) {
      // Ignore deletion errors
    }
  }

  /// Discover live cinder instances, cleaning up stale ones.
  Future<List<_Instance>> _discoverInstances() async {
    final portFiles = await listLogPortFiles();
    final liveInstances = <_Instance>[];

    for (final file in portFiles) {
      // Read the endpoint (port and access token) from the file
      try {
        final portFile = fs.file(file.path);
        final endpoint = LogServerEndpoint.tryParse(
          await portFile.readAsString(),
        );

        if (file.pid > 0 && endpoint != null) {
          // Probe the endpoint without signaling (or resuming) its process.
          final probe = await Socket.connect(
            InternetAddress.loopbackIPv4,
            endpoint.port,
            timeout: const Duration(seconds: 1),
          );
          probe.destroy();
          liveInstances.add((pid: file.pid, endpoint: endpoint));
        } else {
          // Invalid or pre-authentication port file, clean it up
          await _cleanupStalePortFile(file.path);
        }
      } catch (_) {
        // Failed to read port file, clean it up
        await _cleanupStalePortFile(file.path);
      }
    }

    return liveInstances;
  }

  /// Prompt user to select an instance from multiple running instances.
  _Instance? _selectInstance(List<_Instance> instances) {
    stdout.writeln('Multiple cinder instances running:');
    for (var i = 0; i < instances.length; i++) {
      final instance = instances[i];
      stdout.writeln(
        '  ${i + 1}. PID ${instance.pid} (port ${instance.endpoint.port})',
      );
    }
    stdout.write('Select instance [1-${instances.length}]: ');

    final input = stdin.readLineSync();
    if (input == null) return null;

    final selection = int.tryParse(input.trim());
    if (selection == null || selection < 1 || selection > instances.length) {
      stderr.writeln('Invalid selection: $input');
      return null;
    }

    return instances[selection - 1];
  }

  @override
  Future<int> run() async {
    try {
      final pidArg = argResults['pid'] as String?;
      final targetPid = pidArg != null ? int.tryParse(pidArg) : null;
      final mode = argResults['mode'] as String;
      final isGetMode = mode == 'get';

      if (pidArg != null && (targetPid == null || targetPid <= 0)) {
        stderr.writeln('Error: Invalid PID: $pidArg');
        return 1;
      }

      // Discover all live instances
      final instances = await _discoverInstances();

      if (instances.isEmpty) {
        stderr.writeln(
          'Error: No cinder app is running (no log_port files found)',
        );
        stderr.writeln(
          'Make sure a cinder app is running in this directory with its log '
          'server enabled (debug builds, CINDER_LOG_SERVER=1, or '
          'runApp(enableLogServer: true)).',
        );
        return 1;
      }

      LogServerEndpoint endpoint;

      if (targetPid != null) {
        // User specified a PID, find that instance
        final instance = instances.where((i) => i.pid == targetPid).firstOrNull;
        if (instance == null) {
          stderr.writeln('Error: No cinder instance found with PID $targetPid');
          stderr.writeln('Running instances:');
          for (final i in instances) {
            stderr.writeln('  PID ${i.pid} (port ${i.endpoint.port})');
          }
          return 1;
        }
        endpoint = instance.endpoint;
      } else if (instances.length == 1) {
        // Single instance, connect directly
        endpoint = instances.first.endpoint;
      } else {
        // Multiple instances, prompt user to select
        final selected = _selectInstance(instances);
        if (selected == null) {
          return 1;
        }
        endpoint = selected.endpoint;
      }

      // Connect to WebSocket; the token travels in a header, never the URL.
      final url = endpoint.uri(snapshot: isGetMode);
      WebSocket? socket;

      try {
        socket = await endpoint
            .connect(snapshot: isGetMode)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        stderr.writeln('Error: Failed to connect to log server at $url');
        stderr.writeln('The cinder app may have exited. Details: $e');
        return 1;
      }

      // Stream log messages to stdout
      try {
        await for (final message in socket) {
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            stdout.writeln(json['message'] as String);
          } catch (e) {
            stderr.writeln('Warning: Failed to parse log message: $e');
            stdout.writeln(message);
          }
        }
      } catch (e) {
        // Connection closed or error reading
        if (e is! WebSocketException) {
          stderr.writeln('Connection closed: $e');
        }
      } finally {
        await socket.close();
      }
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    }

    return 0;
  }
}

typedef _Instance = ({int pid, LogServerEndpoint endpoint});
