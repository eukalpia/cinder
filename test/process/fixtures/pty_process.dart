import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  switch (arguments.first) {
    case 'arguments':
      stdout.writeln(jsonEncode(arguments.skip(1).toList()));
      exitCode = 7;
    case 'lines':
      stdout.write('first\nsecond\nthird\n');
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
