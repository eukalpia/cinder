import 'dart:async';
import 'dart:io';

import 'package:cinder/cinder.dart';

const String defaultVideoPath = r'C:\Users\name\Videos\movie.mp4';

Future<void> main(List<String> arguments) async {
  final source = _stripWrappingQuotes(
    arguments.isEmpty ? defaultVideoPath : arguments.first,
  );

  if (!_isRemoteSource(source) && !File(source).existsSync()) {
    stderr.writeln('Video file not found: $source');
    stderr.writeln(
      r'Run: dart run example/media_player.dart "C:\Videos\movie.mp4"',
    );
    exitCode = 2;
    return;
  }

  final missingTools = <String>[];
  for (final tool in <String>['ffmpeg', 'ffprobe', 'ffplay']) {
    if (!await _isExecutableAvailable(tool)) {
      missingTools.add(tool);
    }
  }

  if (missingTools.isNotEmpty) {
    stderr.writeln(
      'Missing media tools in PATH: ${missingTools.join(', ')}',
    );
    exitCode = 3;
    return;
  }

  runApp(
    CinderApp(
      home: PlayerScreen(source: source),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.source});

  final String source;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final MediaController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController(
      backend: FfmpegProcessBackend(
        maxVideoWidth: 320,
        maxVideoHeight: 180,
        maxFrameRate: 30,
        lateFrameThreshold: const Duration(milliseconds: 140),
      ),
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _controller.open(widget.source, autoPlay: true);
    } catch (error, stackTrace) {
      stderr.writeln('Unable to open media: $error');
      stderr.writeln(stackTrace);
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Unable to play media'),
            const SizedBox(height: 1),
            Text('$error'),
            const SizedBox(height: 1),
            const Text('Press Q or Ctrl+C to exit'),
          ],
        ),
      );
    }

    return MediaPlayer(
      controller: _controller,
      title: _fileName(widget.source),
      fit: MediaPlayerFit.contain,
      seekStep: const Duration(seconds: 5),
      largeSeekStep: const Duration(seconds: 30),
      volumeStep: 0.05,
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error;
          });
        }
      },
    );
  }
}

Future<bool> _isExecutableAvailable(String executable) async {
  try {
    final result = await Process.run(
      executable,
      const <String>['-version'],
      runInShell: Platform.isWindows,
    ).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  } on TimeoutException {
    return false;
  }
}

bool _isRemoteSource(String source) {
  final uri = Uri.tryParse(source);
  return uri != null &&
      <String>{'http', 'https', 'rtsp', 'rtmp'}.contains(uri.scheme);
}

String _stripWrappingQuotes(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2) {
    return trimmed;
  }
  final first = trimmed[0];
  final last = trimmed[trimmed.length - 1];
  if ((first == '"' && last == '"') ||
      (first == "'" && last == "'")) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _fileName(String source) {
  final normalized = source.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? source : segments.last;
}
