import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  MediaInfo? get info => _info;
  VideoFrame? get frame => _frame;
  MediaPlaybackState get state => _state;
  Object? get error => _error;
  Duration get position => clock.position;
  double get volume => _volume;
  double get speed => _speed;
  int get droppedFrames => _droppedFrames;

  Future<void> open(String source, {bool autoPlay = false}) async {
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
    _state = MediaPlaybackState.disposed;
    _subscription?.cancel();
    unawaited(backend.close());
    super.dispose();
  }
}

class FfmpegMediaBackend implements MediaBackend {
  FfmpegMediaBackend({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.ffplay = 'ffplay',
  });

  final String ffmpeg;
  final String ffprobe;
  final String ffplay;
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

  @override
  Stream<VideoFrame> get videoFrames => _frames.stream;

  @override
  Future<MediaInfo> open(Uri source) async {
    await close();
    _source = source;
    final result = await Process.run(ffprobe, [
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_streams',
      '-show_format',
      _input(source),
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        ffprobe,
        const [],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final streams = (json['streams'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final video = streams.where((s) => s['codec_type'] == 'video').firstOrNull;
    final audio = streams.any((s) => s['codec_type'] == 'audio');
    final format = json['format'] as Map<String, dynamic>?;
    final durationSeconds =
        double.tryParse('${format?['duration'] ?? video?['duration'] ?? 0}') ??
        0;
    final rate = _parseRate(
      '${video?['avg_frame_rate'] ?? video?['r_frame_rate'] ?? ''}',
    );
    _info = MediaInfo(
      duration: Duration(microseconds: (durationSeconds * 1000000).round()),
      width: video?['width'] as int?,
      height: video?['height'] as int?,
      frameRate: rate,
      hasAudio: audio,
      hasVideo: video != null,
    );
    return _info!;
  }

  @override
  Future<void> play({
    required Duration position,
    required double volume,
    required double speed,
  }) async {
    _position = position;
    _volume = volume;
    _speed = speed;
    await _restart();
  }

  @override
  Future<void> pause() async => _stopProcesses();

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    if (_video != null || _audio != null) await _restart();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (_audio != null) await _restart();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_video != null || _audio != null) await _restart();
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
      final frameRate = info.frameRate ?? 30;
      _video = await Process.start(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        _seconds(_position),
        '-i',
        _input(source),
        '-an',
        '-vf',
        'setpts=PTS/${_speed.toStringAsFixed(4)}',
        '-pix_fmt',
        'rgba',
        '-f',
        'rawvideo',
        'pipe:1',
      ]);
      _readFrames(_video!, generation, info.width!, info.height!, frameRate);
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
      _audio = await Process.start(ffplay, [
        '-nodisp',
        '-autoexit',
        '-loglevel',
        'error',
        '-ss',
        _seconds(_position),
        '-volume',
        (_volume * 100).round().toString(),
        '-af',
        filters.join(','),
        _input(source),
      ]);
    }
  }

  Future<void> _readFrames(
    Process process,
    int generation,
    int width,
    int height,
    double frameRate,
  ) async {
    final frameBytes = width * height * 4;
    var buffer = BytesBuilder(copy: false);
    var index = 0;
    await for (final chunk in process.stdout) {
      if (generation != _generation) return;
      buffer.add(chunk);
      final bytes = buffer.takeBytes();
      var offset = 0;
      while (bytes.length - offset >= frameBytes) {
        final pixels = Uint8List.fromList(
          bytes.sublist(offset, offset + frameBytes),
        );
        final timestamp =
            _position +
            Duration(
              microseconds: (index * 1000000 / frameRate / _speed).round(),
            );
        _frames.add(
          VideoFrame(
            pixels: pixels,
            width: width,
            height: height,
            presentationTime: timestamp,
          ),
        );
        offset += frameBytes;
        index++;
      }
      if (offset < bytes.length) buffer.add(bytes.sublist(offset));
    }
  }

  Future<void> _stopProcesses() async {
    _generation++;
    for (final process in <Process?>[_video, _audio]) {
      process?.kill(ProcessSignal.sigterm);
    }
    _video = null;
    _audio = null;
  }

  @override
  Future<void> close() async {
    await _stopProcesses();
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
  });

  final MediaController controller;
  final int? width;
  final int? height;
  final BoxFit fit;
  final Widget? placeholder;

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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.controller.frame;
    if (frame == null) {
      return widget.placeholder ??
          SizedBox(
            width: widget.width?.toDouble(),
            height: widget.height?.toDouble(),
            child: const Text('Loading media...'),
          );
    }
    return Image.rgba(
      frame.pixels,
      pixelWidth: frame.width,
      pixelHeight: frame.height,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
