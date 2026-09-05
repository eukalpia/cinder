import 'dart:async';
import 'dart:io';

/// Serializes terminal control written while an IOSink flush is in flight.
/// IOSink rejects writes while it is bound to its underlying stream consumer.
/// Frame production is separately gated by TerminalBinding; this tail is for
/// cursor/protocol updates and shutdown restoration that cannot wait there.
class SinkOutput {
  SinkOutput(this._sink);
  final IOSink _sink;
  final _pending = StringBuffer();
  Future<void>? _draining;

  void write(String data) {
    if (_draining != null) {
      _pending.write(data);
    } else {
      _sink.write(data);
    }
  }

  Future<void> drain() {
    final existing = _draining;
    if (existing != null) return existing;
    final completer = Completer<void>();
    _draining = completer.future;
    unawaited(_flush(completer));
    return completer.future;
  }

  Future<void> _flush(Completer<void> completer) async {
    try {
      while (true) {
        await _sink.flush();
        if (_pending.isEmpty) break;
        final next = _pending.toString();
        _pending.clear();
        _sink.write(next);
      }
      _draining = null;
      completer.complete();
    } catch (error, stack) {
      _pending.clear();
      _draining = null;
      completer.completeError(error, stack);
    }
  }
}
