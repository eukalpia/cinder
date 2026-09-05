import 'dart:convert';
import 'dart:io';

import 'package:cinder/cinder.dart';
import 'workspace.dart';

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
      model: Workspace(spec),
      fps: (spec['fps'] as num).toDouble(),
    ),
    enableHotReload: false,
  );
}

class _FrameApplication extends StatefulWidget {
  const _FrameApplication({required this.model, required this.fps});

  final Workspace model;
  final double fps;

  @override
  State<_FrameApplication> createState() => _FrameApplicationState();
}

class _FrameApplicationState extends State<_FrameApplication> {
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
      if (widget.model.apply(event.character ?? '')) {
        setState(() {});
        return true;
      }
      return false;
    },
    child: Text(
      widget.model.text(),
      softWrap: false,
      overflow: TextOverflow.clip,
    ),
  );
}
