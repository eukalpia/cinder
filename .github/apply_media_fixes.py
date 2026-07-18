from pathlib import Path

media_path = Path('lib/src/media/media.dart')
text = media_path.read_text()

text = text.replace(
    '  Future<void> close();\n}',
    '  Future<void> close();\n\n  Future<void> dispose() => close();\n}',
    1,
)

text = text.replace(
    '  int _droppedFrames = 0;\n',
    '  int _droppedFrames = 0;\n  int _openGeneration = 0;\n  bool _disposed = false;\n',
    1,
)

old_controller_open = '''  Future<void> open(String source, {bool autoPlay = false}) async {
    _setState(MediaPlaybackState.loading);
    try {
      _info = await backend.open(_toUri(source));
      await _subscription?.cancel();
      _subscription = backend.videoFrames.listen(_acceptFrame, onError: _fail);
      clock.seek(Duration.zero);
      _setState(MediaPlaybackState.ready);
      if (autoPlay) await play();
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }
'''
new_controller_open = '''  Future<void> open(String source, {bool autoPlay = false}) async {
    if (_disposed) {
      throw StateError('The media controller has been disposed.');
    }
    final generation = ++_openGeneration;
    _setState(MediaPlaybackState.loading);
    try {
      final info = await backend.open(_toUri(source));
      if (_disposed || generation != _openGeneration) {
        await backend.close();
        return;
      }
      _info = info;
      await _subscription?.cancel();
      _subscription = backend.videoFrames.listen(_acceptFrame, onError: _fail);
      clock.seek(Duration.zero);
      _setState(MediaPlaybackState.ready);
      if (autoPlay && !_disposed && generation == _openGeneration) {
        await play();
      }
    } catch (error) {
      if (_disposed || generation != _openGeneration) {
        return;
      }
      _fail(error);
      rethrow;
    }
  }
'''
if old_controller_open not in text:
    raise SystemExit('MediaController.open block not found')
text = text.replace(old_controller_open, new_controller_open, 1)

old_controller_dispose = '''  @override
  void dispose() {
    _state = MediaPlaybackState.disposed;
    _subscription?.cancel();
    unawaited(backend.close());
    super.dispose();
  }
'''
new_controller_dispose = '''  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _openGeneration++;
    _state = MediaPlaybackState.disposed;
    _subscription?.cancel();
    unawaited(backend.dispose());
    super.dispose();
  }
'''
if old_controller_dispose not in text:
    raise SystemExit('MediaController.dispose block not found')
text = text.replace(old_controller_dispose, new_controller_dispose, 1)

backend_start = text.index(
    '  @override\n  Future<MediaInfo> open(Uri source) async {',
    text.index('class FfmpegMediaBackend'),
)
backend_end = text.index('\n  @override\n  Future<void> play({', backend_start)
backend_open = '''  @override
  Future<MediaInfo> open(Uri source) async {
    _ensureActive();
    await _stopProcesses();
    _source = null;
    _info = null;
    _position = Duration.zero;
    final generation = ++_generation;

    final result = await Process.run(
      ffprobe,
      <String>[
        '-v',
        'error',
        '-print_format',
        'json',
        '-show_streams',
        '-show_format',
        _input(source),
      ],
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        ffprobe,
        const <String>[],
        result.stderr.toString(),
        result.exitCode,
      );
    }

    final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final streams = (json['streams'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final video = streams
        .where((stream) => stream['codec_type'] == 'video')
        .firstOrNull;
    final audio = streams.any((stream) => stream['codec_type'] == 'audio');
    final format = json['format'] as Map<String, dynamic>?;
    final durationSeconds = double.tryParse(
          '${format?['duration'] ?? video?['duration'] ?? 0}',
        ) ??
        0;
    final rate = _parseRate(
      '${video?['avg_frame_rate'] ?? video?['r_frame_rate'] ?? ''}',
    );
    final info = MediaInfo(
      duration: Duration(
        microseconds: (durationSeconds * 1000000).round(),
      ),
      width: video?['width'] as int?,
      height: video?['height'] as int?,
      frameRate: rate,
      hasAudio: audio,
      hasVideo: video != null,
    );

    if (_disposed || generation != _generation) {
      throw StateError('Media open was cancelled.');
    }

    _source = source;
    _info = info;
    return info;
  }
'''
text = text[:backend_start] + backend_open + text[backend_end:]

text = text.replace(
    '  Future<void> dispose() async {\n    if (_disposed) {',
    '  @override\n  Future<void> dispose() async {\n    if (_disposed) {',
    1,
)

video_player_start = text.index('class VideoPlayer extends StatefulWidget {')
video_player = '''class VideoViewport {
  const VideoViewport({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoViewport &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

VideoViewport fitVideoViewport({
  required int maxWidth,
  required int maxHeight,
  required int sourceWidth,
  required int sourceHeight,
  double cellHeightToWidthRatio = 2,
}) {
  final safeMaxWidth = math.max(1, maxWidth);
  final safeMaxHeight = math.max(1, maxHeight);
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return VideoViewport(width: safeMaxWidth, height: safeMaxHeight);
  }

  final targetCellAspect =
      sourceWidth / sourceHeight * cellHeightToWidthRatio;
  final availableAspect = safeMaxWidth / safeMaxHeight;
  if (availableAspect > targetCellAspect) {
    return VideoViewport(
      width: math.max(1, (safeMaxHeight * targetCellAspect).round()),
      height: safeMaxHeight,
    );
  }
  return VideoViewport(
    width: safeMaxWidth,
    height: math.max(1, (safeMaxWidth / targetCellAspect).round()),
  );
}

class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.adaptive = true,
    this.reservedRows = 0,
    this.cellHeightToWidthRatio = 2,
  })  : assert(width == null || width > 0),
        assert(height == null || height > 0),
        assert(reservedRows >= 0),
        assert(cellHeightToWidthRatio > 0);

  final MediaController controller;

  /// Maximum width in cells when [adaptive] is true.
  /// Otherwise this is the exact requested width.
  final int? width;

  /// Maximum height in rows when [adaptive] is true.
  /// Otherwise this is the exact requested height.
  final int? height;

  final BoxFit fit;
  final Widget? placeholder;

  /// Rebuilds against the real parent constraints after terminal resize.
  final bool adaptive;

  /// Rows kept free for controls rendered inside the same constrained area.
  final int reservedRows;

  /// Approximate physical terminal-cell height divided by its width.
  final double cellHeightToWidthRatio;

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.adaptive) {
      return _buildSized(widget.width, widget.height);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = widget.controller.frame;
        final info = widget.controller.info;
        final sourceWidth = frame?.width ?? info?.width ?? 16;
        final sourceHeight = frame?.height ?? info?.height ?? 9;

        final constraintWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.floor()
            : (widget.width ?? 80);
        final rawConstraintHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight.floor()
            : (widget.height ?? 24);
        final constraintHeight = math.max(
          1,
          rawConstraintHeight - widget.reservedRows,
        );
        final availableWidth = math.max(
          1,
          widget.width == null
              ? constraintWidth
              : math.min(widget.width!, constraintWidth),
        );
        final availableHeight = math.max(
          1,
          widget.height == null
              ? constraintHeight
              : math.min(widget.height!, constraintHeight),
        );
        final viewport = fitVideoViewport(
          maxWidth: availableWidth,
          maxHeight: availableHeight,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          cellHeightToWidthRatio: widget.cellHeightToWidthRatio,
        );

        return Center(
          child: _buildSized(viewport.width, viewport.height),
        );
      },
    );
  }

  Widget _buildSized(int? width, int? height) {
    final frame = widget.controller.frame;
    if (frame == null) {
      final placeholder = widget.placeholder ?? const Text('Loading media...');
      return SizedBox(
        width: width?.toDouble(),
        height: height?.toDouble(),
        child: Center(child: placeholder),
      );
    }

    return Image.rgba(
      frame.pixels,
      pixelWidth: frame.width,
      pixelHeight: frame.height,
      width: width,
      height: height,
      fit: widget.fit,
    );
  }
}
'''
text = text[:video_player_start] + video_player
media_path.write_text(text)

test_path = Path('test/media_controller_test.dart')
tests = test_path.read_text()
tests = tests.replace(
    "import 'dart:typed_data';\n",
    "import 'dart:io';\nimport 'dart:typed_data';\n",
    1,
)

viewport_tests = '''  test('video viewport expands while preserving terminal aspect', () {
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

'''
tests = tests.replace('void main() {\n', 'void main() {\n' + viewport_tests, 1)

lifecycle_tests = '''
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

    final directory = await Directory.systemTemp.createTemp('cinder_media_open_');
    addTearDown(() => directory.delete(recursive: true));
    final probe = File('${directory.path}/ffprobe');
    await probe.writeAsString('''#!/bin/sh
sleep 0.15
printf '%s\\n' '{"streams":[{"codec_type":"video","width":2,"height":2,"avg_frame_rate":"30/1"}],"format":{"duration":"1"}}'
''');
    await Process.run('chmod', <String>['+x', probe.path]);

    final media = File('${directory.path}/sample.mp4')..writeAsBytesSync(<int>[]);
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
'''
tests = tests.replace(
    '\n}\n\nclass _Backend implements MediaBackend {',
    lifecycle_tests + '\n}\n\nclass _Backend implements MediaBackend {',
    1,
)

tests += '''

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
'''
test_path.write_text(tests)
