import 'package:cinder/cinder.dart' hide isEmpty;
import 'package:test/test.dart';

const _ctrlG = KeyboardEvent(
  logicalKey: LogicalKey.keyG,
  modifiers: ModifierKeys(ctrl: true),
);

void main() {
  tearDown(() {
    if (debugMode) toggleDebugMode();
  });

  Future<CinderTester> create({bool? debugOverlayShortcutEnabled}) async {
    final tester = await CinderTester.create(
      debugOverlayShortcutEnabled: debugOverlayShortcutEnabled,
    );
    addTearDown(tester.dispose);
    return tester;
  }

  Widget recorder(List<KeyboardEvent> keys) => Focusable(
    focused: true,
    onKeyEvent: (event) {
      keys.add(event);
      return true;
    },
    child: const Text('app'),
  );

  group('test binding Ctrl+G', () {
    test('matches the terminal binding default', () async {
      final tester = await create();
      final binding = CinderBinding.instance as CinderTestBinding;
      final keys = <KeyboardEvent>[];
      await tester.pumpWidget(recorder(keys));

      await tester.sendKeyEvent(_ctrlG);

      expect(binding.debugOverlayShortcutEnabled, isTrue);
      expect(debugMode, isTrue);
      expect(keys, isEmpty);
    });

    test('reaches the application when the shortcut is disabled', () async {
      final tester = await create(debugOverlayShortcutEnabled: false);
      final keys = <KeyboardEvent>[];
      await tester.pumpWidget(recorder(keys));

      await tester.sendKeyEvent(_ctrlG);

      expect(debugMode, isFalse);
      expect(keys, [same(_ctrlG)]);
    });
  });

  group('CinderApp performance overlay', () {
    bool hasOverlay() {
      var found = false;
      void visit(Element element) {
        if (element.widget is DebugOverlay) found = true;
        element.visitChildren(visit);
      }

      visit(CinderBinding.instance.rootElement!);
      return found;
    }

    test('is not installed unless requested', () async {
      final tester = await create();
      await tester.pumpWidget(const CinderApp(child: Text('app')));
      await tester.pump();

      expect(hasOverlay(), isFalse);
      expect(tester.terminalState, isNot(containsText('DEBUG MODE')));
    });

    test('is shown on request without a runApp overlay', () async {
      final tester = await create(debugOverlayShortcutEnabled: false);
      await tester.pumpWidget(
        const CinderApp(
          debug: CinderDebugOptions(showPerformanceOverlay: true),
          child: Text('app'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(hasOverlay(), isTrue);
      expect(debugMode, isTrue);
      expect(tester.terminalState, containsText('DEBUG MODE'));
      expect(
        tester.terminalState,
        isNot(containsText('Ctrl+G')),
        reason: 'the shortcut is disabled, so the hint would be wrong',
      );
    });

    test('reuses an overlay installed above it', () async {
      final tester = await create();
      await tester.pumpWidget(
        const DebugOverlay(
          child: CinderApp(
            debug: CinderDebugOptions(showPerformanceOverlay: true),
            child: Text('app'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      var overlays = 0;
      void visit(Element element) {
        if (element.widget is DebugOverlay) overlays++;
        element.visitChildren(visit);
      }

      visit(CinderBinding.instance.rootElement!);
      expect(overlays, 1);
      expect(tester.terminalState, containsText('(Ctrl+G to close)'));
    });
  });
}
