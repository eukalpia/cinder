import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'media.dart';

/// Desktop FFmpeg backend with bounded video decoding and FFplay audio.
///
/// The backend owns all spawned processes and terminates the complete process
/// tree on Windows. Audio and video restart from the same captured position
/// after seek, volume, or playback-speed changes.
class FfmpegProcessBackend implements MediaBackend {
  FfmpegProcessBackend({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.ffplay = 'ffplay',
    this.maxVideoWidth = 320,
    this.maxVideoHeight = 180,
    this.maxFrameRate = 30,
    this.lateFrameThreshold = const Duration(milliseconds: 140),
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

  Process? _videoProcess;
  Process? _audioProcess;
  Stopwatch? _sessionWatch;
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

  bool get _isRunning => _videoProcess != null || _audioProcess != null;

  @override
  Stream<VideoFrame> get videoFrames => _frames.stream;

  @override
  Future<MediaInfo> open(Uri source) async {
    _ensureActive();
    await _stopProcesses(preservePosition: false);
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

    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('FFprobe returned invalid JSON.');
    }

    final streams = (decoded['streams'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    Map<String, dynamic>? video;
    for (final stream in streams) {
      if (stream['codec_type'] == 'video') {
        video = stream;
        break;
      }
    }

    final hasAudio = streams.any(
      (stream) => stream['codec_type'] == 'audio',
    );
    final format = decoded['format'] as Map<String, dynamic>?;
    final durationSeconds = double.tryParse(
          '${format?['duration'] ?? video?['duration'] ?? 0}',
        ) ??
        0;
    final frameRate = _parseRate(
      '${video?['avg_frame_rate'] ?? video?['r_frame_rate'] ?? ''}',
    );

    final info = MediaInfo(
      duration: Duration(
        microseconds: (durationSeconds * Duration.microsecondsPerSecond).round(),
      ),
      width: _asInt(video?['width']),
      height: _asInt(video?['height']),
      frameRate: frameRate,
      hasAudio: hasAudio,
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
    _position = _clampPosition(position);
    _volume = volume.clamp(0, 1).toDouble();
    _speed = _validateSpeed(speed);
    await _restart();
  }

  @override
  Future<void> pause() async {
    _ensureActive();
    await _stopProcesses(preservePosition: true);
  }

  @override
  Future<void> seek(Duration position) async {
    _ensureActive();
    final wasRunning = _isRunning;
    _position = _clampPosition(position);
    if (wasRunning) {
      await _restart();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureActive();
    final wasRunning = _isRunning;
    if (wasRunning) {
      _captureCurrentPosition();
    }
    _volume = volume.clamp(0, 1).toDouble();
    if (wasRunning) {
      await _restart();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _ensureActive();
    final wasRunning = _isRunning;
    if (wasRunning) {
      _captureCurrentPosition();
    }
    _speed = _validateSpeed(speed);
    if (wasRunning) {
      await _restart();
    }
  }

  Future<void> _restart() async {
    final source = _source;
    final info = _info;
    if (source == null || info == null) {
      throw StateError('No media is open.');
    }

    await _stopProcesses(preservePosition: false);
    final generation = ++_generation;
    final sessionWatch = Stopwatch()..start();
    _sessionWatch = sessionWatch;

    try {
      if (info.hasVideo && info.width != null && info.height != null) {
        await _startVideo(
          source: source,
          info: info,
          generation: generation,
          sessionWatch: sessionWatch,
        );
      }
      if (info.hasAudio) {
        await _startAudio(source: source, generation: generation);
      }
    } catch (_) {
      await _stopProcesses(preservePosition: false);
      rethrow;
    }
  }

  Future<void> _startVideo({
    required Uri source,
    required MediaInfo info,
    required int generation,
    required Stopwatch sessionWatch,
  }) async {
    final outputSize = _fitSize(info.width!, info.height!);
    final sourceRate = info.frameRate ?? maxFrameRate;
    final outputRate =
        math.min(sourceRate, maxFrameRate).clamp(1, 240).toDouble();
    final stderrBuffer = StringBuffer();

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
      runInShell: Platform.isWindows,
    );

    _videoProcess = process;
    await process.stdin.close();
    unawaited(_captureStderr(process, stderrBuffer));
    unawaited(
      _readFrames(
        process: process,
        generation: generation,
        width: outputSize.width,
        height: outputSize.height,
        frameRate: outputRate,
        sessionWatch: sessionWatch,
      ),
    );
    unawaited(
      _watchProcess(
        process: process,
        generation: generation,
        label: 'video decoder',
        stderrBuffer: stderrBuffer,
        audio: false,
      ),
    );
  }

  Future<void> _startAudio({
    required Uri source,
    required int generation,
  }) async {
    final stderrBuffer = StringBuffer();
    final process = await Process.start(
      ffplay,
      <String>[
        '-hide_banner',
        '-nodisp',
        '-autoexit',
        '-loglevel',
        'error',
        '-ss',
        _seconds(_position),
        '-vn',
        '-volume',
        (_volume * 100).round().toString(),
        '-af',
        _audioFilters(_speed).join(','),
        _input(source),
      ],
      runInShell: Platform.isWindows,
    );

    _audioProcess = process;
    await process.stdin.close();
    unawaited(_captureStderr(process, stderrBuffer));
    unawaited(
      _watchProcess(
        process: process,
        generation: generation,
        label: 'audio player',
        stderrBuffer: stderrBuffer,
        audio: true,
      ),
    );
  }

  Future<void> _readFrames({
    required Process process,
    required int generation,
    required int width,
    required int height,
    required double frameRate,
    required Stopwatch sessionWatch,
  }) async {
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
          microseconds: (index * Duration.microsecondsPerSecond / frameRate / _speed)
              .round(),
        );
        final lead = relativePresentationTime - sessionWatch.elapsed;
        if (lead > Duration.zero) {
          await Future<void>.delayed(lead);
        }
        if (_disposed || generation != _generation) {
          return;
        }

        final lateness = sessionWatch.elapsed - relativePresentationTime;
        if (lateness <= lateFrameThreshold && !_frames.isClosed) {
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

  Future<void> _captureStderr(
    Process process,
    StringBuffer target,
  ) async {
    try {
      await for (final line in process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
        if (target.length < 8192) {
          target.writeln(line);
        }
      }
    } catch (_) {
      // The process may have been terminated during shutdown or seek.
    }
  }

  Future<void> _watchProcess({
    required Process process,
    required int generation,
    required String label,
    required StringBuffer stderrBuffer,
    required bool audio,
  }) async {
    final code = await process.exitCode;

    if (audio) {
      if (identical(_audioProcess, process)) {
        _audioProcess = null;
      }
    } else if (identical(_videoProcess, process)) {
      _videoProcess = null;
    }

    if (_disposed || generation != _generation || code == 0 || _frames.isClosed) {
      return;
    }

    final details = stderrBuffer.toString().trim();
    _frames.addError(
      ProcessException(
        label,
        const <String>[],
        details.isEmpty ? '$label exited with code $code.' : details,
        code,
      ),
    );
  }

  void _captureCurrentPosition() {
    final watch = _sessionWatch;
    if (watch == null) {
      return;
    }
    _position = _clampPosition(
      _position +
          Duration(
            microseconds: (watch.elapsedMicroseconds * _speed).round(),
          ),
    );
  }

  Future<void> _stopProcesses({required bool preservePosition}) async {
    if (preservePosition) {
      _captureCurrentPosition();
    }
    _sessionWatch = null;
    _generation++;

    final processes = <Process>{
      if (_videoProcess != null) _videoProcess!,
      if (_audioProcess != null) _audioProcess!,
    };
    _videoProcess = null;
    _audioProcess = null;

    if (processes.isEmpty) {
      return;
    }

    await Future.wait(
      processes.map(_terminateProcess),
      eagerError: false,
    );
  }

  Future<void> _terminateProcess(Process process) async {
    try {
      await process.stdin.close();
    } catch (_) {
      // stdin may already be closed.
    }

    try {
      if (Platform.isWindows) {
        await Process.run(
          'taskkill',
          <String>['/PID', '${process.pid}', '/T', '/F'],
          runInShell: true,
        ).timeout(const Duration(seconds: 2));
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    } catch (_) {
      process.kill();
    }

    try {
      await process.exitCode.timeout(const Duration(milliseconds: 800));
      return;
    } on TimeoutException {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }

    try {
      await process.exitCode.timeout(const Duration(milliseconds: 800));
    } catch (_) {
      // The OS has already reclaimed the process.
    }
  }

  void _installShutdownHooks() {
    try {
      _sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        unawaited(_stopProcesses(preservePosition: false));
      });
    } catch (_) {
      // Signal watching is not available on every host.
    }

    if (!Platform.isWindows) {
      try {
        _sigtermSubscription = ProcessSignal.sigterm.watch().listen((_) {
          unawaited(_stopProcesses(preservePosition: false));
        });
      } catch (_) {}
      try {
        _sighupSubscription = ProcessSignal.sighup.watch().listen((_) {
          unawaited(_stopProcesses(preservePosition: false));
        });
      } catch (_) {}
    }
  }

  Duration _clampPosition(Duration value) {
    final duration = _info?.duration;
    if (value < Duration.zero) {
      return Duration.zero;
    }
    if (duration != null && value > duration) {
      return duration;
    }
    return value;
  }

  _FrameSize _fitSize(int sourceWidth, int sourceHeight) {
    final scale = math.min(
      1.0,
      math.min(
        maxVideoWidth / sourceWidth,
        maxVideoHeight / sourceHeight,
      ),
    );
    var width = math.max(2, (sourceWidth * scale).round()).toInt();
    var height = math.max(2, (sourceHeight * scale).round()).toInt();
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
      throw StateError('The FFmpeg process backend has been disposed.');
    }
  }

  @override
  Future<void> close() async {
    await _stopProcesses(preservePosition: false);
    _source = null;
    _info = null;
    _position = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stopProcesses(preservePosition: false);
    await _sigintSubscription?.cancel();
    await _sigtermSubscription?.cancel();
    await _sighupSubscription?.cancel();
    if (!_frames.isClosed) {
      await _frames.close();
    }
    _source = null;
    _info = null;
  }

  static double _validateSpeed(double speed) {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'Speed must be positive.');
    }
    return speed;
  }

  static List<String> _audioFilters(double speed) {
    final filters = <String>[];
    var remaining = speed;
    while (remaining > 2) {
      filters.add('atempo=2.0');
      remaining /= 2;
    }
    while (remaining < 0.5) {
      filters.add('atempo=0.5');
      remaining /= 0.5;
    }
    filters.add('atempo=${remaining.toStringAsFixed(4)}');
    return filters;
  }

  static String _input(Uri source) {
    return source.scheme == 'file' ? source.toFilePath() : source.toString();
  }

  static String _seconds(Duration value) {
    return (value.inMicroseconds / Duration.microsecondsPerSecond)
        .toStringAsFixed(6);
  }

  static int? _asInt(Object? value) {
    return switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
  }

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
