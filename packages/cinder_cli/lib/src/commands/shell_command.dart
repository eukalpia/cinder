import 'dart:async';
import 'dart:io';

import 'package:cinder/cinder.dart';
import 'package:cinder_cli/src/deps/fs.dart';
import 'package:cinder_cli/src/deps/log.dart';
import 'package:cinder_cli/utils/cli_command.dart';

class ShellCommand extends CliCommand {
  ShellCommand();

  @override
  String get description =>
      'Start a Cinder shell that apps can render into from an IDE or debugger.';

  @override
  String get name => 'shell';

  @override
  Future<int> run() async {
    if (Platform.isWindows) {
      log('The Cinder shell requires Unix domain sockets on macOS or Linux.');
      return 1;
    }

    log('Starting cinder shell server...');
    await ensureCinderDirectoryExists();
    final socketPath = getShellSocketPath();
    final socketFile = fs.file(socketPath);
    if (await fs.type(socketPath) != FileSystemEntityType.notFound) {
      await socketFile.delete();
    }

    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final handleFile = fs.file(getShellHandlePath());
    final stopped = Completer<void>();
    Socket? activeClient;
    Future<void>? clientTask;
    StreamSubscription<Socket>? serverSubscription;
    StreamSubscription<List<int>>? inputSubscription;
    final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];

    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    try {
      await handleFile.writeAsString(socketPath);
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        signalSubscriptions.add(signal.watch().listen((_) => stop()));
      }
      if (stdin.hasTerminal) {
        stdin.echoMode = false;
        stdin.lineMode = false;
      }
      inputSubscription = stdin.listen((data) {
        if (data.contains(3)) {
          stop();
        } else {
          activeClient?.add(data);
        }
      });
      serverSubscription = server.listen(
        (client) {
          if (activeClient != null || stopped.isCompleted) {
            client.destroy();
            return;
          }
          activeClient = client;
          clientTask = _handleClient(client)
              .catchError((Object error) {
                stderr.writeln('Shell client disconnected: $error');
              })
              .whenComplete(() {
                client.destroy();
                activeClient = null;
                if (stdout.hasTerminal) stdout.write(EscapeCodes.mainBuffer);
              });
        },
        onError: stopped.completeError,
        onDone: stop,
      );

      log('Shell server ready at: $socketPath');
      log('Waiting for cinder app to connect...');
      log('Press Ctrl+C to stop the shell.');
      await stopped.future;
    } finally {
      await serverSubscription?.cancel();
      await server.close();
      activeClient?.destroy();
      await clientTask;
      await inputSubscription?.cancel();
      for (final subscription in signalSubscriptions) {
        await subscription.cancel();
      }
      if (stdout.hasTerminal) {
        stdout.write(EscapeCodes.disable.values.join(''));
        stdout.write(EscapeCodes.mainBuffer);
        stdout.write(EscapeCodes.showCursor);
      }
      if (stdin.hasTerminal) {
        stdin.echoMode = true;
        stdin.lineMode = true;
      }
      if (await handleFile.exists()) await handleFile.delete();
      if (await fs.type(socketPath) != FileSystemEntityType.notFound) {
        await socketFile.delete();
      }
    }
    return 0;
  }

  Future<void> _handleClient(Socket client) async {
    StreamSubscription<ProcessSignal>? resizeSubscription;
    try {
      _sendTerminalSize(client);
      resizeSubscription = ProcessSignal.sigwinch.watch().listen((_) {
        _sendTerminalSize(client);
      });
      await for (final data in client) {
        stdout.add(data);
      }
    } finally {
      await resizeSubscription?.cancel();
    }
  }

  /// Send terminal size to client using custom OSC sequence
  /// Format: ESC ] 9999 ; `<cols>` ; `<rows>` BEL
  void _sendTerminalSize(Socket client) {
    if (stdout.hasTerminal) {
      final cols = stdout.terminalColumns;
      final rows = stdout.terminalLines;

      // Use OSC 9999 as our custom sequence for terminal size
      // This won't interfere with normal terminal output
      final sizeSequence = '\x1b]9999;$cols;$rows\x07';
      client.add(sizeSequence.codeUnits);
    }
  }
}
