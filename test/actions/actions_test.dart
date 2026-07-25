import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

final class _SaveIntent extends Intent {
  const _SaveIntent();
}

void main() {
  test('Shortcuts resolves an intent through the nearest Actions scope',
      () async {
    var invocations = 0;
    await testCinder('actions and shortcuts', (tester) async {
      await tester.pumpWidget(
        Actions(
          actions: <Type, Action<dynamic>>{
            _SaveIntent: CallbackAction<_SaveIntent>(
              onInvoke: (_) {
                invocations++;
                return null;
              },
            ),
          },
          child: Shortcuts(
            autofocus: true,
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKey.keyS, control: true):
                  const _SaveIntent(),
            },
            child: const Text('Editor'),
          ),
        ),
      );

      await tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.keyS,
          modifiers: ModifierKeys(ctrl: true),
        ),
      );
      expect(invocations, 1);
    });
  });

  test('Command matching considers labels, categories and keywords', () {
    const command = Command(
      id: 'file.save',
      label: 'Save file',
      category: 'File',
      keywords: <String>['write', 'persist'],
      intent: _SaveIntent(),
    );
    expect(command.matches('save'), isTrue);
    expect(command.matches('file persist'), isTrue);
    expect(command.matches('deploy'), isFalse);
  });
}

// CommandPalette is covered separately because it owns focus and list state.
