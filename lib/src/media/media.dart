import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cinder/cinder.dart';

enum MediaPlaybackState {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
  disposed,
}

class MediaInfo {
  const MediaInfo({
    required this.duration,
    this.width,
    this.height,
    this.frameRate,
    this.hasAudio = false,
    this.hasVideo = false,
  });

  final Duration duration;
  final int? width;
  final int? height;
  final double? frameRate;
  final bool hasAudio;
  final bool hasVideo;
}

class VideoFrame {
  const VideoFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.presentationTime,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final Duration presentationTime;
}

abstract class MediaBackend {
  Stream<VideoFrame> get videoFrames;
  Future<MediaInfo> open(Uri source);
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  });
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> close();

  Future<void> dispose() => close();
}

class MediaClock {
  final Stopwatch _watch = Stopwatch();
  Duration _anchor = Duration.zero;
  double _speed = 1;

  Duration get position =>
      _anchor +
      Duration(microseconds: (_watch.elapsedMicroseconds * _speed).round());
  bool get isRunning => _watch.isRunning;

  void start(Duration position, {double speed = 1}) {
    _anchor = position;
    _speed = speed;
    _watch
      ..reset()
      ..start();
  }

  void pause() {
    _anchor = position;
    _watch.stop();
  }

  void seek(Duration position) {
    final running = _watch.isRunning;
    _anchor = position;
    _watch.reset();
    if (running) _watch.start();
  }

  void setSpeed(double speed) {
    final running = _watch.isRunning;
    _anchor = position;
    _watch.reset();
    _speed = speed;
    if (running) _watch.start();
  }
}

class MediaController extends ChangeNotifier {
  MediaController({MediaBackend? backend})
      : backend = backend ?? FfmpegMediaBackend();

  final MediaBackend backend;
  final MediaClock clock = MediaClock();
  StreamSubscription<VideoFrame>? _subscription;
  MediaInfo? _info;
  VideoFrame? _frame;
  MediaPlaybackState _state = MediaPlaybackState.idle;
  Object? _error;
  double _volume = 1;
  double _speed = 1;
  int _droppedFrames = 0;
  int _openGeneration = 0;
  bool _disposed = false;

  MediaInfo? get info => _info;
  VideoFrame? get frame => _frame;
  MediaPlaybackState get state => _state;
  Object? get error => _error;
  Duration get position => clock.position;
  double get volume => _volume;
  double get speed => _speed;
  int get droppedFrames => _droppedFrames;

  Future<void> open(String source, {bool autoPlay = false}) async {
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

  Future<void> play() async {
    if (_info == null) throw StateError('Open media before playback.');
    await backend.play(position: position, volume: _volume, speed: _speed);
    clock.start(position, speed: _speed);
    _setState(MediaPlaybackState.playing);
  }

  Future<void> pause() async {
    clock.pause();
    await backend.pause();
    _setState(MediaPlaybackState.paused);
  }

  Future<void> seek(Duration value) async {
    final duration = _info?.duration ?? Duration.zero;
    final target = value < Duration.zero
        ? Duration.zero
        : (value > duration ? duration : value);
    clock.seek(target);
    _frame = null;
    await backend.seek(target);
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1).toDouble();
    await backend.setVolume(_volume);
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Playback speed must be positive.',
      );
    }
    _speed = value;
    clock.setSpeed(value);
    await backend.setSpeed(value);
    notifyListeners();
  }

  void _acceptFrame(VideoFrame candidate) {
    final lateness = position - candidate.presentationTime;
    if (clock.isRunning && lateness > const Duration(milliseconds: 80)) {
      _droppedFrames++;
      return;
    }
    _frame = candidate;
    notifyListeners();
  }

  void _setState(MediaPlaybackState value) {
    _state = value;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = error;
    _state = MediaPlaybackState.error;
    notifyListeners();
  }

  static Uri _toUri(String source) {
    final parsed = Uri.tryParse(source);
    if (parsed != null && parsed.hasScheme) return parsed;
    return File(source).absolute.uri;
  }

  @override
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
}

class FfmpegMediaBackend implements MediaBackend {
  FfmpegMediaBackend({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.ffplay = 'ffplay',
    this.maxVideoWidth = 240,
    this.maxVideoHeight = 135,
    this.maxFrameRate = 30,
    this.lateFrameThreshold = const Duration(milliseconds: 120),
  })  : assert(maxVideoWidth > 0),
        assert(maxVideoHeight > 0),
        assert(maxFrameRate > 0) {
    _installShutdownHooks();
  }

  final String ffmpeg;
  final String ffprobe;
  final String ffplay;
  final int maxVideoWidth;
  final int maxVideoHeight;
  final double maxFrameRate;
  final Duration lateFrameThreshold;

  final StreamController<VideoFrame> _frames =
      StreamController<VideoFrame>.broadcast(sync: true);
  Process? _video;
  Process? _audio;
  Uri? _source;
  MediaInfo? _info;
  Duration _position = Duration.zero;
  double _volume = 1;
  double _speed = 1;
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<ProcessSignal>? _sigintSubscription;
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  StreamSubscription<ProcessSignal>? _sighupSubscription;

  @override
  Stream<VideoFrame> get videoFrames => _frames.stream;

  @override
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
    final video =
        streams.where((stream) => stream['codec_type'] == 'video').firstOrNull;
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

  @override
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  }) async {
    _ensureActive();
    _position = position;
    _volume = volume;
    _speed = speed;
    await _restart();
  }

  @override
  Future<void> pause() => _stopProcesses();

  @override
  Future<void> seek(Duration position) async {
    _ensureActive();
    _position = position;
    if (_video != null || _audio != null) {
      await _restart();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureActive();
    _volume = volume;
    if (_audio != null) {
      await _restart();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _ensureActive();
    _speed = speed;
    if (_video != null || _audio != null) {
      await _restart();
    }
  }

  Future<void> _restart() async {
    final source = _source;
    final info = _info;
    if (source == null || info == null) {
      throw StateError('No media is open.');
    }
    await _stopProcesses();
    final generation = ++_generation;

    if (info.hasVideo && info.width != null && info.height != null) {
      final outputSize = _fitSize(info.width!, info.height!);
      final sourceRate = info.frameRate ?? maxFrameRate;
      final outputRate =
          math.min(sourceRate, maxFrameRate).clamp(1, 240).toDouble();
      final stderrBuffer = StringBuffer();
      final playbackWatch = Stopwatch()..start();
      final process = await Process.start(
          ffmpeg,
          <String>[
            '-hide_banner',
            '-nostdin',
            '-loglevel',
            'error',
            '-ss',
            _seconds(_position),
            '-i',
            _input(source),
            '-map',
            '0:v:0',
            '-an',
            '-sn',
            '-dn',
            '-vf',
            'scale=${outputSize.width}:${outputSize.height}:'
                'flags=fast_bilinear,'
                'fps=${outputRate.toStringAsFixed(3)},'
                'setpts=PTS/${_speed.toStringAsFixed(4)}',
            '-pix_fmt',
            'rgba',
            '-f',
            'rawvideo',
            'pipe:1',
          ],
          runInShell: Platform.isWindows);
      _video = process;
      unawaited(_captureStderr(process, stderrBuffer));
      unawaited(
        _readFrames(
          process,
          generation,
          outputSize.width,
          outputSize.height,
          outputRate,
          playbackWatch,
        ),
      );
      unawaited(
        _watchProcess(process, generation, 'video decoder', stderrBuffer),
      );
    }

    if (info.hasAudio) {
      final filters = <String>[];
      var remaining = _speed;
      while (remaining > 2) {
        filters.add('atempo=2.0');
        remaining /= 2;
      }
      while (remaining < 0.5) {
        filters.add('atempo=0.5');
        remaining /= 0.5;
      }
      filters.add('atempo=${remaining.toStringAsFixed(4)}');
      final stderrBuffer = StringBuffer();
      final process = await Process.start(
          ffplay,
          <String>[
            '-nodisp',
            '-autoexit',
            '-nostdin',
            '-loglevel',
            'error',
            '-ss',
            _seconds(_position),
            '-vn',
            '-volume',
            (_volume * 100).round().toString(),
            '-af',
            filters.join(','),
            _input(source),
          ],
          runInShell: Platform.isWindows);
      _audio = process;
      unawaited(_captureStderr(process, stderrBuffer));
      unawaited(
        _watchProcess(process, generation, 'audio player', stderrBuffer),
      );
    }
  }

  Future<void> _readFrames(
    Process process,
    int generation,
    int width,
    int height,
    double frameRate,
    Stopwatch playbackWatch,
  ) async {
    final frameBytes = width * height * 4;
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    await for (final chunk in process.stdout) {
      if (_disposed || generation != _generation) {
        return;
      }
      buffer.add(chunk);
      final bytes = buffer.takeBytes();
      var offset = 0;
      while (bytes.length - offset >= frameBytes) {
        if (_disposed || generation != _generation) {
          return;
        }
        final relativePresentationTime = Duration(
          microseconds: (index * 1000000 / frameRate / _speed).round(),
        );
        final lead = relativePresentationTime - playbackWatch.elapsed;
        if (lead > Duration.zero) {
          await Future<void>.delayed(lead);
        }
        if (_disposed || generation != _generation) {
          return;
        }
        final lateness = playbackWatch.elapsed - relativePresentationTime;
        if (lateness <= lateFrameThreshold) {
          _frames.add(
            VideoFrame(
              pixels: Uint8List.fromList(
                bytes.sublist(offset, offset + frameBytes),
              ),
              width: width,
              height: height,
              presentationTime: _position + relativePresentationTime,
            ),
          );
        }
        offset += frameBytes;
        index++;
      }
      if (offset < bytes.length) {
        buffer.add(bytes.sublist(offset));
      }
    }
  }

  Future<void> _captureStderr(Process process, StringBuffer target) async {
    await for (final line in process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      if (target.length < 8192) {
        target.writeln(line);
      }
    }
  }

  Future<void> _watchProcess(
    Process process,
    int generation,
    String label,
    StringBuffer stderrBuffer,
  ) async {
    final exitCode = await process.exitCode;
    if (_disposed || generation != _generation || exitCode == 0) {
      return;
    }
    final details = stderrBuffer.toString().trim();
    _frames.addError(
      ProcessException(
        label,
        const <String>[],
        details.isEmpty ? '$label exited with code $exitCode.' : details,
        exitCode,
      ),
    );
  }

  Future<void> _stopProcesses() async {
    _generation++;
    final processes = <Process>{
      if (_video != null) _video!,
      if (_audio != null) _audio!,
    };
    _video = null;
    _audio = null;
    await Future.wait(processes.map(_terminateProcess), eagerError: false);
  }

  Future<void> _terminateProcess(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run(
                'taskkill',
                <String>[
                  '/PID',
                  '${process.pid}',
                  '/T',
                  '/F',
                ],
                runInShell: true)
            .timeout(const Duration(seconds: 2));
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    } catch (_) {
      process.kill();
    }
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 700));
      return;
    } on TimeoutException {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 700));
    } catch (_) {}
  }

  void _installShutdownHooks() {
    try {
      _sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        unawaited(_stopProcesses());
      });
    } catch (_) {}
    if (!Platform.isWindows) {
      try {
        _sigtermSubscription = ProcessSignal.sigterm.watch().listen((_) {
          unawaited(_stopProcesses());
        });
      } catch (_) {}
      try {
        _sighupSubscription = ProcessSignal.sighup.watch().listen((_) {
          unawaited(_stopProcesses());
        });
      } catch (_) {}
    }
  }

  _FrameSize _fitSize(int sourceWidth, int sourceHeight) {
    final scale = math.min(
      1.0,
      math.min(maxVideoWidth / sourceWidth, maxVideoHeight / sourceHeight),
    );
    var width = math.max(2, (sourceWidth * scale).round());
    var height = math.max(2, (sourceHeight * scale).round());
    if (width.isOdd) {
      width--;
    }
    if (height.isOdd) {
      height--;
    }
    return _FrameSize(width, height);
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('The FFmpeg media backend has been disposed.');
    }
  }

  @override
  Future<void> close() async {
    await _stopProcesses();
    _source = null;
    _info = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stopProcesses();
    await _sigintSubscription?.cancel();
    await _sigtermSubscription?.cancel();
    await _sighupSubscription?.cancel();
    if (!_frames.isClosed) {
      await _frames.close();
    }
    _source = null;
    _info = null;
  }

  static String _input(Uri source) =>
      source.scheme == 'file' ? source.toFilePath() : source.toString();

  static String _seconds(Duration value) =>
      (value.inMicroseconds / 1000000).toStringAsFixed(6);

  static double? _parseRate(String value) {
    final parts = value.split('/');
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator != null && denominator != null && denominator != 0) {
        return numerator / denominator;
      }
    }
    return double.tryParse(value);
  }
}

class _FrameSize {
  const _FrameSize(this.width, this.height);

  final int width;
  final int height;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}

class VideoViewport {
  const VideoViewport({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoViewport && other.width == width && other.height == height;

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

  final targetCellAspect = sourceWidth / sourceHeight * cellHeightToWidthRatio;
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
