import 'dart:async';

import 'media.dart';

/// A media controller that guarantees a visible preview frame after seeking.
///
/// Some process backends do not start a decoder when [seek] is called while
/// playback is paused. The base controller clears its current frame before
/// delegating the seek, which can otherwise leave the UI on an endless
/// "Opening video" placeholder.
///
/// This controller temporarily starts playback for paused seeks, waits for a
/// frame at or after the requested position, then restores the paused state.
class ResilientMediaController extends MediaController {
  ResilientMediaController({MediaBackend? backend}) : super(backend: backend);

  Future<void> _seekQueue = Future<void>.value();
  int _seekGeneration = 0;

  @override
  Future<void> seek(Duration value) {
    final generation = ++_seekGeneration;
    final completer = Completer<void>();

    _seekQueue = _seekQueue.then<void>((_) async {
      try {
        await _performSeek(value, generation);
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    return completer.future;
  }

  Future<void> _performSeek(Duration value, int generation) async {
    final duration = info?.duration ?? Duration.zero;
    final target = value < Duration.zero
        ? Duration.zero
        : (value > duration ? duration : value);

    final restorePause = state != MediaPlaybackState.playing;
    if (restorePause) {
      await play();
    }

    final previousFrame = frame;
    await super.seek(target);

    await _waitForPreview(
      target: target,
      previousFrame: previousFrame,
      generation: generation,
    );

    if (restorePause && generation == _seekGeneration) {
      await pause();
    }
  }

  Future<void> _waitForPreview({
    required Duration target,
    required VideoFrame? previousFrame,
    required int generation,
  }) async {
    final completer = Completer<void>();
    Timer? timeout;

    void listener() {
      if (generation != _seekGeneration) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final current = frame;
      if (current == null || identical(current, previousFrame)) {
        return;
      }

      final distance = current.presentationTime - target;
      if (distance.inMilliseconds.abs() <= 1500 && !completer.isCompleted) {
        completer.complete();
      }
    }

    addListener(listener);
    timeout = Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future;
    } finally {
      timeout.cancel();
      removeListener(listener);
    }
  }

  @override
  void dispose() {
    _seekGeneration++;
    super.dispose();
  }
}
