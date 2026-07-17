import 'dart:async';
import 'dart:typed_data';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('media controller opens and controls backend', () async {
    final backend = _Backend();
    final controller = MediaController(backend: backend);

    await controller.open('sample.mp4');
    expect(controller.state, MediaPlaybackState.ready);

    await controller.play();
    expect(controller.state, MediaPlaybackState.playing);

    backend.frames.add(
      VideoFrame(
        pixels: Uint8List(4),
        width: 1,
        height: 1,
        presentationTime: Duration.zero,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.frame, isNotNull);

    await controller.pause();
    expect(controller.state, MediaPlaybackState.paused);
    controller.dispose();
  });
}

class _Backend implements MediaBackend {
  final StreamController<VideoFrame> frames = StreamController<VideoFrame>();

  @override
  Stream<VideoFrame> get videoFrames => frames.stream;

  @override
  Future<MediaInfo> open(Uri source) async =>
      const MediaInfo(duration: Duration(seconds: 10), hasVideo: true);

  @override
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> close() async {
    await frames.close();
  }
}
