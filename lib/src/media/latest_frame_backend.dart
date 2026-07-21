import 'dart:async';

import 'media.dart';

/// A bounded display adapter that keeps only the newest decoded video frame.
///
/// Terminal rendering can be slower than FFmpeg decoding, especially when the
/// Unicode block fallback is active. An ordinary stream queue would preserve
/// every old frame and make playback drift farther behind real time. This
/// adapter stores one pending frame and publishes it at [displayFrameRate].
class LatestFrameMediaBackend implements MediaBackend {
  LatestFrameMediaBackend({
    required this.backend,
    this.displayFrameRate = 60,
  }) : assert(displayFrameRate > 0);

  final MediaBackend backend;
  final double displayFrameRate;

  final StreamController<VideoFrame> _output =
      StreamController<VideoFrame>.broadcast(sync: true);

  StreamSubscription<VideoFrame>? _subscription;
  Timer? _displayTimer;
  VideoFrame? _pendingFrame;
  VideoFrame? _lastEmittedFrame;
  bool _disposed = false;

  @override
  Stream<VideoFrame> get videoFrames => _output.stream;

  @override
  Future<MediaInfo> open(Uri source) async {
    _ensureActive();
    await _subscription?.cancel();
    _pendingFrame = null;
    _lastEmittedFrame = null;

    _subscription = backend.videoFrames.listen(
      (frame) {
        _pendingFrame = frame;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_output.isClosed) {
          _output.addError(error, stackTrace);
        }
      },
    );

    _startDisplayTimer();
    return backend.open(source);
  }

  void _startDisplayTimer() {
    _displayTimer?.cancel();
    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / displayFrameRate).round(),
    );
    _displayTimer = Timer.periodic(interval, (_) {
      final frame = _pendingFrame;
      if (frame == null || identical(frame, _lastEmittedFrame)) {
        return;
      }
      _lastEmittedFrame = frame;
      if (!_output.isClosed) {
        _output.add(frame);
      }
    });
  }

  @override
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  }) {
    return backend.play(position: position, volume: volume, speed: speed);
  }

  @override
  Future<void> pause() => backend.pause();

  @override
  Future<void> seek(Duration position) {
    _pendingFrame = null;
    return backend.seek(position);
  }

  @override
  Future<void> setVolume(double volume) => backend.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => backend.setSpeed(speed);

  @override
  Future<void> close() async {
    _pendingFrame = null;
    _lastEmittedFrame = null;
    await backend.close();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('The latest-frame media backend has been disposed.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _displayTimer?.cancel();
    _displayTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await backend.dispose();
    if (!_output.isClosed) {
      await _output.close();
    }
  }
}
