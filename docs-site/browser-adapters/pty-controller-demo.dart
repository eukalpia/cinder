import 'package:cinder/cinder.dart';

/// Deterministic browser sandbox for the native PTY controller example.
///
/// This is intentionally not a shell, SSH session, or operating-system process.
void main() {
  runApp(const PtySandboxApp());
}

class PtySandboxApp extends StatefulWidget {
  const PtySandboxApp({super.key});

  @override
  State<PtySandboxApp> createState() => _PtySandboxAppState();
}

class _PtySandboxAppState extends State<PtySandboxApp> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = <String>[
    'Cinder PTY browser sandbox',
    'No native process has been started.',
    'Type `help` to inspect deterministic commands.',
    '',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit(String input) {
    final command = input.trim();
    if (command.isEmpty) return;

    setState(() {
      _lines.add('sandbox@cinder:~\$ $command');
      _lines.addAll(_execute(command));
      _controller.clear();
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollController.scrollToEnd();
    });
  }

  List<String> _execute(String command) {
    if (command == 'help') {
      return const <String>[
        'help      show this command list',
        'status    show the sandbox capability boundary',
        'ls        list deterministic virtual files',
        'cat demo  print a virtual file',
        'clear     clear the transcript',
        'echo TEXT print TEXT',
      ];
    }
    if (command == 'status') {
      return const <String>[
        'backend: deterministic browser sandbox',
        'pty: unavailable',
        'process execution: unavailable',
        'keyboard and Cinder TextField: active',
      ];
    }
    if (command == 'ls') {
      return const <String>['README.md  demo  capabilities.json'];
    }
    if (command == 'cat demo') {
      return const <String>[
        'Widget → Element → RenderObject → Buffer → WebBackend',
      ];
    }
    if (command == 'clear') {
      _lines.clear();
      return const <String>[];
    }
    if (command.startsWith('echo ')) {
      return <String>[command.substring(5)];
    }
    return <String>['command not available in sandbox: $command'];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.magenta)),
      child: Column(
        children: [
          Container(
            color: const Color.fromRGB(28, 22, 40),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  'PTY CONTROLLER / BROWSER SANDBOX',
                  style: TextStyle(
                    color: Colors.magenta,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('NO OS PROCESS', style: TextStyle(color: Colors.yellow)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              children: _lines
                  .map(
                    (line) => Text(
                      line,
                      style: TextStyle(
                        color: line.startsWith('sandbox@')
                            ? Colors.green
                            : null,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: BoxBorder(top: BorderSide(color: Colors.gray)),
            ),
            child: Row(
              children: [
                const Text(
                  'sandbox@cinder:~\$ ',
                  style: TextStyle(color: Colors.green),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    placeholder: 'help',
                    onSubmitted: _submit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
