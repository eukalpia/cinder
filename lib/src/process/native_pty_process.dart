import 'dart:io';
import 'dart:typed_data';

/// Operating-system operations used by the asynchronous transport.
abstract class NativePtyProcess {
  int get pid;

  /// Null means no bytes are ready; an empty list means the output has closed.
  Uint8List? read();
  Future<void> write(Uint8List bytes);
  void stopWriting();
  int? pollExit();
  void resize(int rows, int columns);
  bool kill(ProcessSignal signal);

  /// Starts terminal shutdown while output continues to drain.
  Future<void> finish();
  Future<void> close();
}
