import 'dart:io';

/// Browsers cannot create local operating-system terminals.
class PtyHandler {
  int? get pid => null;
  Stream<String> get output => const Stream.empty();
  Future<int> get exitCode =>
      Future.error(UnsupportedError('Local PTYs require a native platform'));
  Future<void> start({required int columns, required int rows}) =>
      Future.error(UnsupportedError('Local PTYs require a native platform'));
  void write(String data) =>
      throw UnsupportedError('Local PTYs require a native platform');
  void writeBytes(List<int> data) =>
      throw UnsupportedError('Local PTYs require a native platform');
  void resize(int rows, int columns) {}
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
  Future<void> dispose() async {}
}

class PtyHandlerFactory {
  static PtyHandler create({
    required String command,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
  }) => PtyHandler();
}
