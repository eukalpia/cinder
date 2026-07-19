import 'package:cinder/cinder.dart';

/// Browser sandbox for the native clipboard diagnostics example.
///
/// It exercises Cinder's in-process clipboard and OSC 52 output without claiming
/// direct access to the host operating-system clipboard.
void main() {
  runApp(const ClipboardSandboxApp());
}

class ClipboardSandboxApp extends StatefulWidget {
  const ClipboardSandboxApp({super.key});

  @override
  State<ClipboardSandboxApp> createState() => _ClipboardSandboxAppState();
}

class _ClipboardSandboxAppState extends State<ClipboardSandboxApp> {
  final List<String> _events = <String>[
    'Browser sandbox ready.',
    'The host OS clipboard is intentionally not read without browser permission.',
  ];
  int _sequence = 1;
  String _buffer = ClipboardManager.paste() ?? '(empty)';

  void _copy() {
    final value = 'Cinder clipboard sample #$_sequence';
    _sequence++;
    ClipboardManager.copy(value);
    final osc52Sent = Clipboard.copy(value);
    setState(() {
      _buffer = ClipboardManager.paste() ?? '(empty)';
      _events.insert(
        0,
        'Copied "$value"; OSC 52 ${osc52Sent ? 'emitted' : 'unavailable'}.',
      );
    });
  }

  void _paste() {
    setState(() {
      _buffer = ClipboardManager.paste() ?? '(empty)';
      _events.insert(0, 'Read the Cinder in-process clipboard buffer.');
    });
  }

  void _reset() {
    ClipboardManager.copy('');
    setState(() {
      _buffer = '(empty)';
      _events
        ..clear()
        ..add('Sandbox state reset.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.keyC) {
          _copy();
          return true;
        }
        if (event.logicalKey == LogicalKey.keyV) {
          _paste();
          return true;
        }
        if (event.logicalKey == LogicalKey.keyR) {
          _reset();
          return true;
        }
        return false;
      },
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.magenta),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  ' CLIPBOARD / BROWSER SANDBOX ',
                  style: TextStyle(
                    color: Colors.magenta,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('NO NATIVE CLIPBOARD CLAIM', style: TextStyle(color: Colors.yellow)),
              ],
            ),
            const SizedBox(height: 1),
            Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                border: BoxBorder.all(color: Colors.gray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cinder buffer', style: TextStyle(color: Colors.cyan)),
                  Text(_buffer, style: const TextStyle(color: Colors.brightWhite)),
                ],
              ),
            ),
            const SizedBox(height: 1),
            const Text(
              '[C] copy sample   [V] paste buffer   [R] reset',
              style: TextStyle(color: Colors.yellow),
            ),
            const SizedBox(height: 1),
            const Text('Event ledger', style: TextStyle(color: Colors.cyan)),
            Expanded(
              child: ListView(
                children: _events
                    .take(12)
                    .map((event) => Text('› $event'))
                    .toList(growable: false),
              ),
            ),
            const Text(
              'OSC 52 support depends on the terminal host. Browser permission APIs are outside this sandbox.',
              style: TextStyle(color: Colors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
