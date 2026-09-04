import 'dart:convert';
import 'dart:io';

import 'package:cinder/cinder.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: cinder-benchmark <workload.json>');
    exitCode = 64;
    return;
  }
  final spec =
      jsonDecode(File(arguments.single).readAsStringSync())
          as Map<String, dynamic>;
  await runApp(
    _FrameApplication(
      frames: List<String>.from(spec['frames'] as List),
      fps: (spec['fps'] as num).toDouble(),
    ),
    enableHotReload: false,
  );
}

class _FrameApplication extends StatefulWidget {
  const _FrameApplication({required this.frames, required this.fps});

  final List<String> frames;
  final double fps;

  @override
  State<_FrameApplication> createState() => _FrameApplicationState();
}

class _FrameApplicationState extends State<_FrameApplication> {
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance
      ..setTargetFps(widget.fps)
      ..enableFrameRateLimiting = true;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (event) {
      if (event.character == 'q') {
        TerminalBinding.instance.requestShutdown();
        return true;
      }
      if (event.character == 'n') {
        setState(() => _frame++);
        return true;
      }
      return false;
    },
    child: Text(
      widget.frames[_frame % widget.frames.length],
      softWrap: false,
      overflow: TextOverflow.clip,
    ),
  );
}
