import 'dart:io';

final class PortableDebugLog {
  PortableDebugLog(String path) : _file = File(path);

  final File _file;

  void clear() {
    if (_file.existsSync()) {
      _file.deleteSync();
    }
  }

  void write(String message) {
    _file.writeAsStringSync('$message\n', mode: FileMode.append);
  }
}
