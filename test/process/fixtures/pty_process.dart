import 'dart:convert';
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  switch (arguments.first) {
    case 'arguments':
      stdout.writeln(jsonEncode(arguments.skip(1).toList()));
      exitCode = 7;
    case 'lines':
      stdout.write('first\nsecond\nthird\n');
    case 'environment':
      stdout.writeln('SHELL:${Platform.environment['SHELL']}');
      stdout.writeln('VALUE:${Platform.environment['CINDER_PTY_TEST']}');
    case 'exit':
      exitCode = int.parse(arguments[1]);
    case 'signal':
      Process.killPid(pid, ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(seconds: 10));
    case 'stalled':
      if (stdin.hasTerminal) {
        stdin.echoMode = false;
        stdin.lineMode = false;
      }
      stdout.writeln('READY:$pid');
      await stdout.flush();
      Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => stdout.writeln('ALIVE'),
      );
      await Completer<void>().future;
    case 'descendant':
      final child = await Process.start('/bin/sh', [
        '-c',
        r'trap "" TERM HUP; echo GRANDCHILD:$$; while :; do sleep 1; done',
      ]);
      child.stdout.listen(stdout.add);
      child.stderr.listen(stderr.add);
      await child.exitCode;
    case 'dimensions':
      if (stdin.hasTerminal) stdin.echoMode = false;
      void report() {
        stdout.writeln(
          'TTY:${stdin.hasTerminal}:${stdout.hasTerminal}:${stderr.hasTerminal}',
        );
        stdout.writeln(
          'SIZE:${stdout.terminalColumns}:${stdout.terminalLines}',
        );
      }
      report();
      await for (final line
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line == 'exit') break;
        if (line == 'size') report();
      }
    case 'interactive':
      if (stdin.hasTerminal) stdin.echoMode = false;
      stdout.writeln('READY:$pid');
      await for (final line
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line == 'exit') break;
        stdout.writeln('INPUT:$line');
      }
    case 'fragmented':
      if (stdin.hasTerminal) stdin.echoMode = false;
      stdout.write('hel');
      await stdout.flush();
      await stdin.first;
      stdout.write('lo\nsecond\n\nthird');
  }
  await stdout.flush();
}
