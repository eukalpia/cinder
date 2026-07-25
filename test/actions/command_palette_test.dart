import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

final class _RunIntent extends Intent {
  const _RunIntent();
}

void main() {
  test('CommandPalette filters and invokes commands from the keyboard',
      () async {
    var invoked = false;
    await testCinder('command palette', (tester) async {
      await tester.pumpWidget(
        Actions(
          actions: <Type, Action<dynamic>>{
            _RunIntent: CallbackAction<_RunIntent>(
              onInvoke: (_) {
                invoked = true;
                return null;
              },
            ),
          },
          child: const SizedBox(
            width: 48,
            height: 12,
            child: CommandPalette(
              commands: <Command>[
                Command(
                  id: 'run.tests',
                  label: 'Run tests',
                  intent: _RunIntent(),
                ),
                Command(
                  id: 'open.settings',
                  label: 'Open settings',
                  intent: NamedIntent('settings'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.terminalState, containsText('Run tests'));
      await tester.enterText('run');
      await tester.sendKey(LogicalKey.enter);
      expect(invoked, isTrue);
    });
  });
}
