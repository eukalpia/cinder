import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/backend/stdio_backend.dart';

/// Reports how [StdioBackend] routes signals on stderr.
///
/// The parent sends SIGTERM before anything listens to `terminationStream`,
/// then writes a line to stdin; the request must still be delivered.
Future<void> main() async {
  final backend = StdioBackend();
  backend.shutdownStream!.listen((_) => stderr.writeln('interrupt'));
  stderr.writeln('ready');

  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  backend.terminationStream.listen((_) {
    stderr.writeln('terminated');
    backend.dispose();
    exit(0);
  });
}
