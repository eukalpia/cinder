import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('video viewport expands while preserving terminal aspect', () {
    final viewport = fitVideoViewport(
      maxWidth: 200,
      maxHeight: 55,
      sourceWidth: 1920,
      sourceHeight: 1080,
    );

    expect(viewport, const VideoViewport(width: 196, height: 55));
  });

  test('video viewport is constrained by terminal width', () {
    final viewport = fitVideoViewport(
      maxWidth: 80,
      maxHeight: 40,
      sourceWidth: 1920,
      sourceHeight: 1080,
    );

    expect(viewport, const VideoViewport(width: 80, height: 23));
  });

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
  test('disposing during auto play does not start playback later', () async {
    final backend = _DelayedBackend();
    final controller = MediaController(backend: backend);

    final opening = controller.open('sample.mp4', autoPlay: true);
    controller.dispose();
    backend.completeOpen();
    await opening;

    expect(backend.playCalls, 0);
    expect(backend.disposeCalls, 1);
  });

  test('closing during ffprobe cancels the pending open atomically', () async {
    if (Platform.isWindows) {
      return;
    }

    final directory =
        await Directory.systemTemp.createTemp('cinder_media_open_');
    addTearDown(() => directory.delete(recursive: true));
    final probe = File('${directory.path}/ffprobe');
    await probe.writeAsString('''#!/bin/sh
sleep 0.15
printf '%s\n' '{"streams":[{"codec_type":"video","width":2,"height":2,"avg_frame_rate":"30/1"}],"format":{"duration":"1"}}'
''');
    await Process.run('chmod', <String>['+x', probe.path]);

    final media = File('${directory.path}/sample.mp4')
      ..writeAsBytesSync(<int>[]);
    final backend = FfmpegMediaBackend(
      ffprobe: probe.path,
      ffmpeg: '/bin/true',
      ffplay: '/bin/true',
    );
    addTearDown(backend.dispose);

    final opening = backend.open(media.uri);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await backend.close();

    await expectLater(
      opening,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
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

  @override
  Future<void> dispose() => close();
}

class _DelayedBackend implements MediaBackend {
  final Completer<MediaInfo> _openCompleter = Completer<MediaInfo>();
  final StreamController<VideoFrame> _frames = StreamController<VideoFrame>();
  int playCalls = 0;
  int disposeCalls = 0;

  void completeOpen() {
    if (!_openCompleter.isCompleted) {
      _openCompleter.complete(
        const MediaInfo(duration: Duration(seconds: 1), hasVideo: true),
      );
    }
  }

  @override
  Stream<VideoFrame> get videoFrames => _frames.stream;

  @override
  Future<MediaInfo> open(Uri source) => _openCompleter.future;

  @override
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  }) async {
    playCalls++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_frames.isClosed) {
      await _frames.close();
    }
  }
}
