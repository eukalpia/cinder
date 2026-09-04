import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('CinderApp', () {
    test('sets window title on initialization', () async {
      await testCinder('title initialization', (tester) async {
        await tester.pumpWidget(
          CinderApp(title: 'Test App', child: Text('Hello')),
        );

        // The title should be set via OSC sequence
        // We can't easily test the terminal state directly, but we can verify
        // the widget renders correctly
        expect(tester.terminalState, containsText('Hello'));
      });
    });

    test('sets both window title and icon name separately', () async {
      await testCinder('separate title and icon', (tester) async {
        await tester.pumpWidget(
          CinderApp(
            title: 'My Window Title',
            iconName: 'MyApp',
            child: Text('Content'),
          ),
        );

        expect(tester.terminalState, containsText('Content'));
      });
    });

    test('updates title when widget updates', () async {
      await testCinder('title update', (tester) async {
        // Initial state
        await tester.pumpWidget(
          CinderApp(title: 'Initial Title', child: Text('Content')),
        );

        expect(tester.terminalState, containsText('Content'));

        // Update the title
        await tester.pumpWidget(
          CinderApp(title: 'Updated Title', child: Text('Content')),
        );

        expect(tester.terminalState, containsText('Content'));
      });
    });

    test('renders child widget correctly', () async {
      await testCinder('child rendering', (tester) async {
        await tester.pumpWidget(
          CinderApp(
            title: 'Test',
            child: Column(children: [Text('Line 1'), Text('Line 2')]),
          ),
        );

        expect(tester.terminalState, containsText('Line 1'));
        expect(tester.terminalState, containsText('Line 2'));
      });
    });

    test('works without title (optional parameter)', () async {
      await testCinder('no title', (tester) async {
        await tester.pumpWidget(CinderApp(child: Text('No Title Set')));

        expect(tester.terminalState, containsText('No Title Set'));
      });
    });

    test('visual test of CinderApp with title', () async {
      await testCinder('visual with title', (tester) async {
        await tester.pumpWidget(
          CinderApp(
            title: 'Demo Application',
            iconName: 'DemoApp',
            child: Container(
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: Padding(
                padding: EdgeInsets.all(2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CinderApp Demo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Window title: "Demo Application"'),
                    Text('Icon name: "DemoApp"'),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.terminalState, containsText('CinderApp Demo'));
        expect(tester.terminalState, containsText('Demo Application'));
      }, debugPrintAfterPump: true);
    });
  });

  group('CinderApp with Navigator', () {
    test(
      'theme detection preserves the navigator and its pushed route',
      () async {
        final terminal = _DelayedThemeTerminal();
        final binding = CinderTestBinding(terminal: terminal);
        final navigatorKey = GlobalKey<NavigatorState>();
        try {
          binding.attachRootWidget(
            CinderApp(
              navigatorKey: navigatorKey,
              routes: {
                '/': (_) => const Text('Home'),
                '/detail': (_) => const Text('Detail Screen'),
              },
            ),
          );
          await binding.pump();
          final navigator = navigatorKey.currentState!;
          unawaited(navigator.pushNamed('/detail'));
          await binding.pump();
          expect(
            TerminalState(buffer: binding.lastBuffer!, size: binding.size),
            containsText('Detail Screen'),
          );

          terminal.background.complete(const Color.fromRGB(255, 255, 255));
          await Future<void>.delayed(Duration.zero);
          await binding.pump();

          expect(navigatorKey.currentState, same(navigator));
          expect(
            TerminalState(buffer: binding.lastBuffer!, size: binding.size),
            containsText('Detail Screen'),
          );
          expect(TuiTheme.of(navigator.context).brightness, Brightness.light);
        } finally {
          binding.shutdown();
        }
      },
    );

    test('creates navigator with home parameter', () async {
      await testCinder('navigator with home', (tester) async {
        await tester.pumpWidget(
          CinderApp(title: 'Nav Test', home: Text('Home Screen')),
        );

        expect(tester.terminalState, containsText('Home Screen'));
      });
    });

    test('creates navigator with routes', () async {
      await testCinder('navigator with routes', (tester) async {
        await tester.pumpWidget(
          CinderApp(
            title: 'Routes Test',
            routes: {
              '/': (context) => Text('Home Route'),
              '/settings': (context) => Text('Settings Route'),
            },
          ),
        );

        expect(tester.terminalState, containsText('Home Route'));
      });
    });

    test('creates navigator with initialRoute', () async {
      await testCinder('navigator with initial route', (tester) async {
        await tester.pumpWidget(
          CinderApp(
            title: 'Initial Route Test',
            initialRoute: '/settings',
            routes: {
              '/': (context) => Text('Home Route'),
              '/settings': (context) => Text('Settings Route'),
            },
          ),
        );

        expect(tester.terminalState, containsText('Settings Route'));
      });
    });

    test('navigation works with pushNamed', () async {
      await testCinder('push named route', (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          CinderApp(
            title: 'Push Test',
            navigatorKey: navigatorKey,
            routes: {
              '/': (context) => Text('Home'),
              '/detail': (context) => Text('Detail Screen'),
            },
          ),
        );

        expect(tester.terminalState, containsText('Home'));

        // Navigate to detail using the navigator key
        navigatorKey.currentState!.pushNamed('/detail');
        await tester.pump();

        expect(tester.terminalState, containsText('Detail Screen'));
      });
    });

    test('uses child when provided instead of navigator', () async {
      await testCinder('child without navigator', (tester) async {
        await tester.pumpWidget(
          CinderApp(title: 'Child Test', child: Text('Simple Child')),
        );

        expect(tester.terminalState, containsText('Simple Child'));
      });
    });
  });
}

class _DelayedThemeTerminal extends Terminal {
  _DelayedThemeTerminal() : super(_ThemeBackend());

  final background = Completer<Color?>();

  @override
  Future<Color?> getBackgroundColor({
    Duration timeout = const Duration(milliseconds: 100),
  }) => background.future;
}

class _ThemeBackend extends TerminalBackend {
  @override
  void writeRaw(String data) {}

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => null;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void dispose() {}
}
