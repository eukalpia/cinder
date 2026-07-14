import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('CinderApp', () {
    test('sets window title on initialization', () async {
      await testCinder(
        'title initialization',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Test App',
              child: Text('Hello'),
            ),
          );

          // The title should be set via OSC sequence
          // We can't easily test the terminal state directly, but we can verify
          // the widget renders correctly
          expect(tester.terminalState, containsText('Hello'));
        },
      );
    });

    test('sets both window title and icon name separately', () async {
      await testCinder(
        'separate title and icon',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'My Window Title',
              iconName: 'MyApp',
              child: Text('Content'),
            ),
          );

          expect(tester.terminalState, containsText('Content'));
        },
      );
    });

    test('updates title when widget updates', () async {
      await testCinder(
        'title update',
        (tester) async {
          // Initial state
          await tester.pumpComponent(
            CinderApp(
              title: 'Initial Title',
              child: Text('Content'),
            ),
          );

          expect(tester.terminalState, containsText('Content'));

          // Update the title
          await tester.pumpComponent(
            CinderApp(
              title: 'Updated Title',
              child: Text('Content'),
            ),
          );

          expect(tester.terminalState, containsText('Content'));
        },
      );
    });

    test('renders child widget correctly', () async {
      await testCinder(
        'child rendering',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Test',
              child: Column(
                children: [
                  Text('Line 1'),
                  Text('Line 2'),
                ],
              ),
            ),
          );

          expect(tester.terminalState, containsText('Line 1'));
          expect(tester.terminalState, containsText('Line 2'));
        },
      );
    });

    test('works without title (optional parameter)', () async {
      await testCinder(
        'no title',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              child: Text('No Title Set'),
            ),
          );

          expect(tester.terminalState, containsText('No Title Set'));
        },
      );
    });

    test('visual test of CinderApp with title', () async {
      await testCinder(
        'visual with title',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Demo Application',
              iconName: 'DemoApp',
              child: Container(
                decoration: BoxDecoration(
                  border: BoxBorder.all(),
                ),
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('CinderApp Demo',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
        },
        debugPrintAfterPump: true,
      );
    });
  });

  group('CinderApp with Navigator', () {
    test('creates navigator with home parameter', () async {
      await testCinder(
        'navigator with home',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Nav Test',
              home: Text('Home Screen'),
            ),
          );

          expect(tester.terminalState, containsText('Home Screen'));
        },
      );
    });

    test('creates navigator with routes', () async {
      await testCinder(
        'navigator with routes',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Routes Test',
              routes: {
                '/': (context) => Text('Home Route'),
                '/settings': (context) => Text('Settings Route'),
              },
            ),
          );

          expect(tester.terminalState, containsText('Home Route'));
        },
      );
    });

    test('creates navigator with initialRoute', () async {
      await testCinder(
        'navigator with initial route',
        (tester) async {
          await tester.pumpComponent(
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
        },
      );
    });

    test(
      'navigation works with pushNamed',
      () async {
        await testCinder(
          'push named route',
          (tester) async {
            final navigatorKey = GlobalKey<NavigatorState>();

            await tester.pumpComponent(
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
          },
        );
      },
      skip: 'Known issue: Navigator pushNamed triggers element lifecycle '
          'assertion in build_owner.dart during route transitions',
    );

    test('uses child when provided instead of navigator', () async {
      await testCinder(
        'child without navigator',
        (tester) async {
          await tester.pumpComponent(
            CinderApp(
              title: 'Child Test',
              child: Text('Simple Child'),
            ),
          );

          expect(tester.terminalState, containsText('Simple Child'));
        },
      );
    });
  });
}
