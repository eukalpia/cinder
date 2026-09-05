import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// A serial log sender with bounded live backlog and lazily encoded replay.
/// Replay must itself come from a bounded snapshot. Its original strings are
/// retained by the caller; only one replay message is encoded at a time.
@internal
final class LogOutputQueue {
  LogOutputQueue({
    required this.maxBytes,
    required this.maxMessages,
    required this.send,
    required this.onClose,
    Iterable<String> replay = const [],
    this.closeWhenIdle = false,
  }) : _replay = replay.iterator {
    if (maxBytes <= 0 || maxMessages <= 0) {
      throw ArgumentError('Log output limits must be positive');
    }
  }

  final int maxBytes;
  final int maxMessages;
  final Future<void> Function(String) send;
  final void Function() onClose;
  final bool closeWhenIdle;
  Iterator<String>? _replay;
  final Queue<String> _pending = Queue<String>();
  int _pendingBytes = 0;
  int _pendingMessages = 0;
  bool _pumping = false;
  bool _closed = false;

  bool get isClosed => _closed;
  int get pendingBytes => _pendingBytes;

  void add(String message) {
    if (_closed) return;
    final bytes = message.length * 2;
    if (_pendingBytes + bytes > maxBytes || _pendingMessages >= maxMessages) {
      close();
      return;
    }
    _pending.add(message);
    _pendingBytes += bytes;
    _pendingMessages++;
    start();
  }

  void start() {
    if (!_closed && !_pumping) unawaited(_pump());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (!_closed) {
        String message;
        final replay = _replay;
        if (replay != null && replay.moveNext()) {
          message = replay.current;
          if (_pendingBytes + message.length * 2 > maxBytes ||
              _pendingMessages >= maxMessages) {
            close();
            return;
          }
          _pendingBytes += message.length * 2;
          _pendingMessages++;
        } else {
          _replay = null;
          if (_pending.isEmpty) {
            if (closeWhenIdle) close();
            return;
          }
          message = _pending.removeFirst();
        }
        await send(message);
        if (_closed) return;
        _pendingBytes -= message.length * 2;
        _pendingMessages--;
      }
    } catch (_) {
      close();
    } finally {
      _pumping = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    _replay = null;
    _pendingBytes = 0;
    _pendingMessages = 0;
    onClose();
  }
}
