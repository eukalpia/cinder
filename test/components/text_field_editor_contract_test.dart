import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class _DraftHost extends StatefulWidget {
  const _DraftHost({super.key, required this.store});

  final MemoryTextDraftStore store;

  @override
  State<_DraftHost> createState() => _DraftHostState();
}

class _DraftHostState extends State<_DraftHost> {
  String chatId = 'alpha';
  final controller = TextEditingController();

  void showChat(String value) => setState(() => chatId = value);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      maxLines: 4,
      draftKey: chatId,
      draftStore: widget.store,
    );
  }
}

void main() {
  group('TextField editor contract', () {
    test('controller supports atomic undo and redo', () {
      final controller = TextEditingController(text: 'hello');
      controller.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 11),
      );

      expect(controller.canUndo, isTrue);
      expect(controller.undo(), isTrue);
      expect(controller.text, 'hello');
      expect(controller.redo(), isTrue);
      expect(controller.text, 'hello world');
      controller.dispose();
    });

    test('modifier-specific delete runs before ordinary backspace', () async {
      final controller = TextEditingController(text: 'hello world');
      await testCinder('word delete ordering', (tester) async {
        await tester.pumpWidget(
          TextField(controller: controller, autofocus: true),
        );
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.backspace,
            modifiers: ModifierKeys(ctrl: true),
          ),
        );
        expect(controller.text, 'hello ');
      });
      controller.dispose();
    });

    test('editor shortcuts and application shortcuts are separated', () async {
      final controller = TextEditingController(text: 'copy me');
      var appShortcutCount = 0;

      await testCinder('shortcut ownership', (tester) async {
        await tester.pumpWidget(
          TextField(
            controller: controller,
            autofocus: true,
            onAppKeyEvent: (_) {
              appShortcutCount++;
              return true;
            },
          ),
        );

        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 4,
        );
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyC,
            modifiers: ModifierKeys(ctrl: true),
          ),
        );
        expect(appShortcutCount, 0);

        controller.selection = const TextSelection.collapsed(offset: 7);
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyC,
            modifiers: ModifierKeys(ctrl: true),
          ),
        );
        expect(appShortcutCount, 1);
      });
      controller.dispose();
    });

    test('draft follows chat identity without leaking between chats', () async {
      final key = GlobalKey<_DraftHostState>();
      final store = MemoryTextDraftStore();

      await testCinder('chat drafts', (tester) async {
        await tester.pumpWidget(_DraftHost(key: key, store: store));
        await tester.enterText('alpha draft');
        expect(key.currentState!.controller.text, 'alpha draft');

        key.currentState!.showChat('beta');
        await tester.pump();
        expect(key.currentState!.controller.text, '');

        await tester.enterText('beta draft');
        key.currentState!.showChat('alpha');
        await tester.pump();
        expect(key.currentState!.controller.text, 'alpha draft');

        key.currentState!.showChat('beta');
        await tester.pump();
        expect(key.currentState!.controller.text, 'beta draft');
      });
    });

    test('plain Enter sends and Shift+Enter inserts a newline', () async {
      final controller = TextEditingController(text: 'message');
      final submitted = <String>[];

      await testCinder('composer enter behavior', (tester) async {
        await tester.pumpWidget(
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            onSubmitted: submitted.add,
          ),
        );

        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.enter,
            modifiers: ModifierKeys(shift: true),
          ),
        );
        expect(controller.text, 'message\n');
        expect(submitted, hasLength(0));

        await tester.sendEnter();
        expect(submitted, <String>['message\n']);
      });
      controller.dispose();
    });

    test('submit chord is configurable', () async {
      final controller = TextEditingController(text: 'message');
      var submitCount = 0;

      await testCinder('configurable submit', (tester) async {
        await tester.pumpWidget(
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            submitMode: TextFieldSubmitMode.controlOrMetaEnter,
            onSubmitted: (_) => submitCount++,
          ),
        );

        await tester.sendEnter();
        expect(controller.text, 'message\n');
        expect(submitCount, 0);

        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.enter,
            modifiers: ModifierKeys(ctrl: true),
          ),
        );
        expect(submitCount, 1);
      });
      controller.dispose();
    });

    for (final sample in <(String, String)>[
      ('emoji', 'A👨‍👩‍👧‍👦'),
      ('combining character', 'Aé'),
      ('Arabic', 'مرحبا'),
      ('Cyrillic', 'Привет'),
      ('CJK', '你好'),
    ]) {
      test(
        'Backspace preserves grapheme boundaries for ${sample.$1}',
        () async {
          final controller = TextEditingController(text: sample.$2);
          final expected = switch (sample.$1) {
            'emoji' => 'A',
            'combining character' => 'A',
            'Arabic' => 'مرحب',
            'Cyrillic' => 'Приве',
            'CJK' => '你',
            _ => throw StateError('missing expectation'),
          };

          await testCinder('unicode ${sample.$1}', (tester) async {
            await tester.pumpWidget(
              TextField(controller: controller, autofocus: true),
            );
            await tester.sendBackspace();
            expect(controller.text, expected);
          });
          controller.dispose();
        },
      );
    }
  });
}
