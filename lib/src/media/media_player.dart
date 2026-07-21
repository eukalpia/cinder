import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cinder/cinder.dart';

import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import 'media.dart';

/// How video content occupies the available terminal viewport.
enum MediaPlayerFit {
  /// Preserve the complete video with letterboxing when necessary.
  contain,

  /// Fill the complete viewport while cropping the source around its center.
  cover,

  /// Stretch the video to the complete viewport.
  fill,
}

/// A complete terminal media player with keyboard and mouse controls.
///
/// Keyboard shortcuts:
///
/// - Space or K: play/pause
/// - Left/Right or J/L: seek backward/forward
/// - Shift+Left/Right: seek by the large seek interval
/// - Up/Down: volume
/// - M: mute
/// - [ / ]: playback speed
/// - 0..9: jump to a percentage of the duration
/// - F: contain/cover viewport mode
/// - C: show or hide controls
/// - Home/End: beginning/end
/// - Q: close the Cinder application
class MediaPlayer extends StatefulWidget {
  const MediaPlayer({
    super.key,
    required this.controller,
    this.title,
    this.fit = MediaPlayerFit.contain,
    this.showHeader = true,
    this.showControls = true,
    this.autofocus = true,
    this.seekStep = const Duration(seconds: 5),
    this.largeSeekStep = const Duration(seconds: 30),
    this.volumeStep = 0.05,
    this.cellHeightToWidthRatio = 2,
    this.placeholder,
    this.onError,
  })  : assert(volumeStep > 0 && volumeStep <= 1),
        assert(cellHeightToWidthRatio > 0);

  final MediaController controller;
  final String? title;
  final MediaPlayerFit fit;
  final bool showHeader;
  final bool showControls;
  final bool autofocus;
  final Duration seekStep;
  final Duration largeSeekStep;
  final double volumeStep;
  final double cellHeightToWidthRatio;
  final Widget? placeholder;
  final void Function(Object error)? onError;

  @override
  State<MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<MediaPlayer> {
  static const List<double> _playbackSpeeds = <double>[
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    1.75,
    2,
  ];

  Timer? _ticker;
  late MediaPlayerFit _fit;
  late bool _controlsVisible;
  double _lastAudibleVolume = 1;
  Object? _lastReportedError;
  Future<void> _commandQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _fit = widget.fit;
    _controlsVisible = widget.showControls;
    if (widget.controller.volume > 0) {
      _lastAudibleVolume = widget.controller.volume;
    }
    widget.controller.addListener(_changed);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (mounted &&
            widget.controller.state == MediaPlaybackState.playing) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(MediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _lastReportedError = null;
    }
    if (oldWidget.fit != widget.fit) {
      _fit = widget.fit;
    }
    if (oldWidget.showControls != widget.showControls) {
      _controlsVisible = widget.showControls;
    }
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final error = widget.controller.error;
    if (error != null && !identical(error, _lastReportedError)) {
      _lastReportedError = error;
      widget.onError?.call(error);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _enqueue(Future<void> Function() command) {
    _commandQueue = _commandQueue.then<void>((_) async {
      try {
        await command();
      } catch (error) {
        widget.onError?.call(error);
      }
    });
  }

  bool _handleKey(KeyboardEvent event) {
    final key = event.logicalKey;

    if (key == LogicalKey.space || key == LogicalKey.keyK) {
      _enqueue(_togglePlayback);
      return true;
    }
    if (key == LogicalKey.arrowLeft || key == LogicalKey.keyJ) {
      final amount =
          event.isShiftPressed ? widget.largeSeekStep : widget.seekStep;
      _enqueue(() => _seekRelative(_negate(amount)));
      return true;
    }
    if (key == LogicalKey.arrowRight || key == LogicalKey.keyL) {
      final amount =
          event.isShiftPressed ? widget.largeSeekStep : widget.seekStep;
      _enqueue(() => _seekRelative(amount));
      return true;
    }
    if (key == LogicalKey.arrowUp) {
      _enqueue(() => _changeVolume(widget.volumeStep));
      return true;
    }
    if (key == LogicalKey.arrowDown) {
      _enqueue(() => _changeVolume(-widget.volumeStep));
      return true;
    }
    if (key == LogicalKey.keyM) {
      _enqueue(_toggleMute);
      return true;
    }
    if (key == LogicalKey.bracketLeft) {
      _enqueue(() => _changeSpeed(-1));
      return true;
    }
    if (key == LogicalKey.bracketRight) {
      _enqueue(() => _changeSpeed(1));
      return true;
    }
    if (key == LogicalKey.keyF) {
      _toggleFit();
      return true;
    }
    if (key == LogicalKey.keyC) {
      setState(() {
        _controlsVisible = !_controlsVisible;
      });
      return true;
    }
    if (key == LogicalKey.home) {
      _enqueue(() => widget.controller.seek(Duration.zero));
      return true;
    }
    if (key == LogicalKey.end) {
      final duration = widget.controller.info?.duration;
      if (duration != null) {
        _enqueue(() => widget.controller.seek(duration));
      }
      return true;
    }
    if (key == LogicalKey.keyQ) {
      shutdownApp();
      return true;
    }

    final digit = _digitForKey(key);
    if (digit != null) {
      _enqueue(() => _seekFraction(digit / 10));
      return true;
    }

    return false;
  }

  void _toggleFit() {
    setState(() {
      _fit = _fit == MediaPlayerFit.cover
          ? MediaPlayerFit.contain
          : MediaPlayerFit.cover;
    });
  }

  Future<void> _togglePlayback() async {
    final controller = widget.controller;
    if (controller.state == MediaPlaybackState.playing) {
      await controller.pause();
      return;
    }
    if (controller.state == MediaPlaybackState.completed) {
      await controller.seek(Duration.zero);
    }
    await controller.play();
  }

  Future<void> _seekRelative(Duration delta) async {
    await widget.controller.seek(widget.controller.position + delta);
  }

  Future<void> _seekFraction(double fraction) async {
    final duration = widget.controller.info?.duration ?? Duration.zero;
    if (duration <= Duration.zero) {
      return;
    }
    final safeFraction = fraction.clamp(0, 1).toDouble();
    await widget.controller.seek(
      Duration(
        microseconds: (duration.inMicroseconds * safeFraction).round(),
      ),
    );
  }

  Future<void> _changeVolume(double delta) async {
    final target = (widget.controller.volume + delta).clamp(0, 1).toDouble();
    if (target > 0) {
      _lastAudibleVolume = target;
    }
    await widget.controller.setVolume(target);
  }

  Future<void> _toggleMute() async {
    if (widget.controller.volume > 0) {
      _lastAudibleVolume = widget.controller.volume;
      await widget.controller.setVolume(0);
      return;
    }
    await widget.controller.setVolume(
      _lastAudibleVolume <= 0 ? 1 : _lastAudibleVolume,
    );
  }

  Future<void> _changeSpeed(int direction) async {
    final current = widget.controller.speed;
    var index = _playbackSpeeds.indexWhere(
      (speed) => (speed - current).abs() < 0.001,
    );
    if (index < 0) {
      index = _playbackSpeeds.indexWhere((speed) => speed >= current);
      if (index < 0) {
        index = _playbackSpeeds.length - 1;
      }
    }
    final nextIndex = (index + direction)
        .clamp(0, _playbackSpeeds.length - 1)
        .toInt();
    await widget.controller.setSpeed(_playbackSpeeds[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final info = controller.info;

    return Focusable(
      focused: widget.autofocus,
      onKeyEvent: _handleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.showHeader)
            _MediaHeader(
              title: widget.title,
              info: info,
            ),
          Expanded(
            child: VideoFrameSurface(
              frame: controller.frame,
              info: info,
              fit: _fit,
              cellHeightToWidthRatio: widget.cellHeightToWidthRatio,
              placeholder: widget.placeholder,
            ),
          ),
          if (_controlsVisible)
            MediaControls(
              controller: controller,
              fit: _fit,
              onTogglePlayback: () => _enqueue(_togglePlayback),
              onSeekFraction: (fraction) {
                _enqueue(() => _seekFraction(fraction));
              },
              onSeekBackward: () {
                _enqueue(() => _seekRelative(_negate(widget.seekStep)));
              },
              onSeekForward: () {
                _enqueue(() => _seekRelative(widget.seekStep));
              },
              onVolumeDown: () {
                _enqueue(() => _changeVolume(-widget.volumeStep));
              },
              onVolumeUp: () {
                _enqueue(() => _changeVolume(widget.volumeStep));
              },
              onToggleMute: () => _enqueue(_toggleMute),
              onSlower: () => _enqueue(() => _changeSpeed(-1)),
              onFaster: () => _enqueue(() => _changeSpeed(1)),
              onToggleFit: _toggleFit,
            ),
        ],
      ),
    );
  }

  static int? _digitForKey(LogicalKey key) {
    const keys = <LogicalKey>[
      LogicalKey.digit0,
      LogicalKey.digit1,
      LogicalKey.digit2,
      LogicalKey.digit3,
      LogicalKey.digit4,
      LogicalKey.digit5,
      LogicalKey.digit6,
      LogicalKey.digit7,
      LogicalKey.digit8,
      LogicalKey.digit9,
    ];
    final index = keys.indexOf(key);
    return index < 0 ? null : index;
  }

  static Duration _negate(Duration value) {
    return Duration(microseconds: -value.inMicroseconds);
  }
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({required this.title, required this.info});

  final String? title;
  final MediaInfo? info;

  @override
  Widget build(BuildContext context) {
    final dimensions = info?.width != null && info?.height != null
        ? '${info!.width}x${info!.height}'
        : 'probing';
    final fps = info?.frameRate == null
        ? ''
        : ' · ${info!.frameRate!.toStringAsFixed(2)} FPS';
    final label = title == null || title!.isEmpty
        ? '$dimensions$fps'
        : '${title!} · $dimensions$fps';
    return Center(child: Text(label));
  }
}

/// Direct, frame-oriented video rendering without the asynchronous image loader.
class VideoFrameSurface extends StatelessWidget {
  const VideoFrameSurface({
    super.key,
    required this.frame,
    required this.info,
    this.fit = MediaPlayerFit.contain,
    this.cellHeightToWidthRatio = 2,
    this.placeholder,
    this.protocol,
  }) : assert(cellHeightToWidthRatio > 0);

  final VideoFrame? frame;
  final MediaInfo? info;
  final MediaPlayerFit fit;
  final double cellHeightToWidthRatio;
  final Widget? placeholder;
  final ImageProtocol? protocol;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final candidateWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.floor()
            : 80;
        final candidateHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight.floor()
            : 24;
        final maxWidth = candidateWidth < 1 ? 1 : candidateWidth;
        final maxHeight = candidateHeight < 1 ? 1 : candidateHeight;
        final currentFrame = frame;

        if (currentFrame == null) {
          final metadata = info;
          final suffix = metadata?.width != null && metadata?.height != null
              ? ' ${metadata!.width}x${metadata.height}'
              : '';
          return SizedBox(
            width: maxWidth.toDouble(),
            height: maxHeight.toDouble(),
            child: Center(
              child: placeholder ?? Text('Opening video$suffix...'),
            ),
          );
        }

        if (fit == MediaPlayerFit.contain) {
          final viewport = fitVideoViewport(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            sourceWidth: currentFrame.width,
            sourceHeight: currentFrame.height,
            cellHeightToWidthRatio: cellHeightToWidthRatio,
          );
          return Center(
            child: _DirectVideoFrame(
              frame: currentFrame,
              width: viewport.width,
              height: viewport.height,
              fit: BoxFit.fill,
              protocol: protocol,
            ),
          );
        }

        final imageData = fit == MediaPlayerFit.cover
            ? _cropFrameForCover(
                currentFrame,
                targetCellWidth: maxWidth,
                targetCellHeight: maxHeight,
                cellHeightToWidthRatio: cellHeightToWidthRatio,
              )
            : ImageData(
                pixels: currentFrame.pixels,
                width: currentFrame.width,
                height: currentFrame.height,
              );

        return _DirectVideoFrame.data(
          imageData: imageData,
          width: maxWidth,
          height: maxHeight,
          fit: BoxFit.fill,
          protocol: protocol,
        );
      },
    );
  }
}

class _DirectVideoFrame extends SingleChildRenderObjectWidget {
  _DirectVideoFrame({
    required VideoFrame frame,
    required this.width,
    required this.height,
    required this.fit,
    this.protocol,
  }) : imageData = ImageData(
          pixels: frame.pixels,
          width: frame.width,
          height: frame.height,
        );

  const _DirectVideoFrame.data({
    required this.imageData,
    required this.width,
    required this.height,
    required this.fit,
    this.protocol,
  });

  final ImageData imageData;
  final int width;
  final int height;
  final BoxFit fit;
  final ImageProtocol? protocol;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderImage(
      imageData: imageData,
      requestedWidth: width,
      requestedHeight: height,
      fit: fit,
      protocol: protocol,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderImage renderObject) {
    renderObject
      ..imageData = imageData
      ..requestedWidth = width
      ..requestedHeight = height
      ..fit = fit
      ..protocol = protocol;
  }
}

ImageData _cropFrameForCover(
  VideoFrame frame, {
  required int targetCellWidth,
  required int targetCellHeight,
  required double cellHeightToWidthRatio,
}) {
  final targetAspect =
      targetCellWidth / (targetCellHeight * cellHeightToWidthRatio);
  final sourceAspect = frame.width / frame.height;

  var cropX = 0;
  var cropY = 0;
  var cropWidth = frame.width;
  var cropHeight = frame.height;

  if (sourceAspect > targetAspect) {
    final calculated = (frame.height * targetAspect).round();
    cropWidth = calculated < 1 ? 1 : calculated;
    cropX = (frame.width - cropWidth) ~/ 2;
  } else if (sourceAspect < targetAspect) {
    final calculated = (frame.width / targetAspect).round();
    cropHeight = calculated < 1 ? 1 : calculated;
    cropY = (frame.height - cropHeight) ~/ 2;
  }

  if (cropX == 0 &&
      cropY == 0 &&
      cropWidth == frame.width &&
      cropHeight == frame.height) {
    return ImageData(
      pixels: frame.pixels,
      width: frame.width,
      height: frame.height,
    );
  }

  final pixels = Uint8List(cropWidth * cropHeight * 4);
  final sourceStride = frame.width * 4;
  final targetStride = cropWidth * 4;
  for (var row = 0; row < cropHeight; row++) {
    final sourceStart = (cropY + row) * sourceStride + cropX * 4;
    final targetStart = row * targetStride;
    pixels.setRange(
      targetStart,
      targetStart + targetStride,
      frame.pixels,
      sourceStart,
    );
  }

  return ImageData(
    pixels: pixels,
    width: cropWidth,
    height: cropHeight,
  );
}

/// Standalone controls for applications that provide their own video surface.
class MediaControls extends StatelessWidget {
  const MediaControls({
    super.key,
    required this.controller,
    required this.fit,
    required this.onTogglePlayback,
    required this.onSeekFraction,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onVolumeDown,
    required this.onVolumeUp,
    required this.onToggleMute,
    required this.onSlower,
    required this.onFaster,
    required this.onToggleFit,
  });

  final MediaController controller;
  final MediaPlayerFit fit;
  final VoidCallback onTogglePlayback;
  final void Function(double fraction) onSeekFraction;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final VoidCallback onVolumeDown;
  final VoidCallback onVolumeUp;
  final VoidCallback onToggleMute;
  final VoidCallback onSlower;
  final VoidCallback onFaster;
  final VoidCallback onToggleFit;

  @override
  Widget build(BuildContext context) {
    final duration = controller.info?.duration ?? Duration.zero;
    final position = controller.position;
    final progress = duration <= Duration.zero
        ? 0.0
        : (position.inMicroseconds / duration.inMicroseconds)
            .clamp(0, 1)
            .toDouble();
    final playing = controller.state == MediaPlaybackState.playing;
    final muted = controller.volume <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SeekBar(
          progress: progress,
          onSeek: onSeekFraction,
        ),
        Center(
          child: Text(
            '${_formatMediaDuration(position)} / '
            '${_formatMediaDuration(duration)}'
            ' · ${_stateLabel(controller.state)}'
            ' · volume ${(controller.volume * 100).round()}%'
            ' · ${controller.speed.toStringAsFixed(2)}x'
            ' · dropped ${controller.droppedFrames}',
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth.isFinite && constraints.maxWidth < 100;
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ControlButton(
                    label: compact ? '[-]' : '[-5s]',
                    onTap: onSeekBackward,
                  ),
                  const SizedBox(width: 1),
                  _ControlButton(
                    label: playing ? '[Pause]' : '[Play]',
                    onTap: onTogglePlayback,
                  ),
                  const SizedBox(width: 1),
                  _ControlButton(
                    label: compact ? '[+]' : '[+5s]',
                    onTap: onSeekForward,
                  ),
                  const SizedBox(width: 2),
                  _ControlButton(label: '[Vol-]', onTap: onVolumeDown),
                  const SizedBox(width: 1),
                  _ControlButton(
                    label: muted ? '[Unmute]' : '[Mute]',
                    onTap: onToggleMute,
                  ),
                  const SizedBox(width: 1),
                  _ControlButton(label: '[Vol+]', onTap: onVolumeUp),
                  if (!compact) ...<Widget>[
                    const SizedBox(width: 2),
                    _ControlButton(label: '[Slower]', onTap: onSlower),
                    const SizedBox(width: 1),
                    _ControlButton(label: '[Faster]', onTap: onFaster),
                    const SizedBox(width: 2),
                    _ControlButton(
                      label: fit == MediaPlayerFit.cover
                          ? '[Contain]'
                          : '[Fullscreen]',
                      onTap: onToggleFit,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const Center(
          child: Text(
            'Space play/pause · arrows seek/volume · M mute · '
            '[ ] speed · 0-9 jump · F fit · C controls · Q quit',
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.progress, required this.onSeek});

  final double progress;
  final void Function(double fraction) onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final candidateWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.floor()
            : 80;
        final width = candidateWidth < 10 ? 10 : candidateWidth;
        final innerWidth = width - 2 < 1 ? 1 : width - 2;
        final filled = (innerWidth * progress.clamp(0, 1)).round();
        final remaining = innerWidth - filled;
        final empty = remaining < 0 ? 0 : remaining;
        final bar =
            '[${''.padRight(filled, '=')}${''.padRight(empty, '-')}]';

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final fraction = (details.localPosition.dx / width)
                .clamp(0, 1)
                .toDouble();
            onSeek(fraction);
          },
          child: SizedBox(
            width: width.toDouble(),
            height: 1,
            child: Text(bar, softWrap: false),
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(label, softWrap: false),
    );
  }
}

String _formatMediaDuration(Duration value) {
  final rawSeconds = value.inSeconds;
  final seconds = rawSeconds < 0 ? 0 : rawSeconds;
  final hours = seconds ~/ 3600;
  final minutes = seconds.remainder(3600) ~/ 60;
  final remainder = seconds.remainder(60);
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = remainder.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText';
  }
  return '$minuteText:$secondText';
}

String _stateLabel(MediaPlaybackState state) {
  return switch (state) {
    MediaPlaybackState.idle => 'idle',
    MediaPlaybackState.loading => 'loading',
    MediaPlaybackState.ready => 'ready',
    MediaPlaybackState.playing => 'playing',
    MediaPlaybackState.paused => 'paused',
    MediaPlaybackState.completed => 'completed',
    MediaPlaybackState.error => 'error',
    MediaPlaybackState.disposed => 'disposed',
  };
}
