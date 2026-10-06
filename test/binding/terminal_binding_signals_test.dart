import 'dart:async';

import 'package:cinder/cinder.dart' hide isEmpty;
import 'package:test/test.dart';

const _ctrlG = KeyboardEvent(
  logicalKey: LogicalKey.keyG,
  modifiers: ModifierKeys(ctrl: true),
);

void main() {
  tearDown(() {
    if (debugMode) toggleDebugMode();
    CinderBinding.resetInstance();
  });

  /// Starts a binding whose only widget records keys and optionally claims
  /// Ctrl+C. Runs inside a guarded zone so handler errors can be inspected.
  ({TerminalBinding binding, _SignalBackend backend, List<KeyboardEvent> keys})
  start({
    bool? debugOverlayShortcutEnabled,
    bool handleCtrlC = false,
    List<Object>? errors,
  }) {
    final backend = _SignalBackend();
    final keys = <KeyboardEvent>[];
    late TerminalBinding binding;
    runZonedGuarded(
      () {
        binding = TerminalBinding(
          Terminal(backend),
          capabilities: const TerminalCapabilities(
            isInteractive: true,
            supportsRawMode: true,
            supportsAlternateScreen: true,
          ),
          debugOverlayShortcutEnabled: debugOverlayShortcutEnabled,
        );
        binding.initialize();
        binding.attachRootWidget(
          Focusable(
            focused: true,
            onKeyEvent: (event) {
              keys.add(event);
              return handleCtrlC && event.matches(LogicalKey.keyC, ctrl: true);
            },
            child: const Text('app'),
          ),
        );
      },
      (error, stackTrace) {
        if (errors == null) Error.throwWithStackTrace(error, stackTrace);
        errors.add(error);
      },
    );
    addTearDown(binding.shutdown);
    return (binding: binding, backend: backend, keys: keys);
  }

  group('debug overlay shortcut', () {
    test('defaults to enabled when assertions are enabled', () {
      final (:binding, backend: _, keys: _) = start();

      // dart test enables assertions, as debug builds do.
      expect(binding.debugOverlayShortcutEnabled, isTrue);
    });

    test('delivers Ctrl+G to the application when disabled', () {
      final (:binding, backend: _, :keys) = start(
        debugOverlayShortcutEnabled: false,
      );

      binding.dispatchInputEvent(const KeyboardInputEvent(_ctrlG));

      expect(keys, [same(_ctrlG)]);
      expect(debugMode, isFalse);
    });

    test('consumes Ctrl+G and toggles debug mode when enabled', () {
      final (:binding, backend: _, :keys) = start(
        debugOverlayShortcutEnabled: true,
      );

      binding.dispatchInputEvent(const KeyboardInputEvent(_ctrlG));

      expect(keys, isEmpty);
      expect(debugMode, isTrue);
    });

    test('can be changed while the application runs', () {
      final (:binding, backend: _, :keys) = start(
        debugOverlayShortcutEnabled: true,
      );

      binding.debugOverlayShortcutEnabled = false;
      binding.dispatchInputEvent(const KeyboardInputEvent(_ctrlG));

      expect(keys, hasLength(1));
      expect(debugMode, isFalse);
    });
  });

  group('termination', () {
    test('cannot be vetoed by widgets or exit request handlers', () async {
      final (:binding, :backend, :keys) = start(handleCtrlC: true);
      var consulted = 0;
      binding.addExitRequestHandler(() {
        consulted++;
        return AppExitResponse.cancel;
      });

      backend.terminate();
      await pumpEventQueue();

      expect(backend.exitCodes, [0]);
      expect(binding.shouldExit, isTrue);
      expect(keys, isEmpty, reason: 'no synthetic Ctrl+C is dispatched');
      expect(consulted, 0);
    });

    test('restores the terminal before requesting exit', () async {
      final (binding: _, :backend, keys: _) = start(handleCtrlC: true);

      backend.terminate();
      await pumpEventQueue();

      expect(backend.outputAtExit, contains(EscapeCodes.mainBuffer));
      expect(backend.rawModeAtExit, isFalse);
      expect(backend.disposedAtExit, isTrue);
    });
  });

  group('interrupt', () {
    test('a widget handling Ctrl+C keeps the application running', () async {
      final (:binding, :backend, :keys) = start(handleCtrlC: true);

      backend.interrupt();
      await pumpEventQueue();

      expect(keys.single.matches(LogicalKey.keyC, ctrl: true), isTrue);
      expect(backend.exitCodes, isEmpty);
      expect(binding.shouldExit, isFalse);
    });

    test('exits with code 0 when nothing objects', () async {
      final (:binding, :backend, :keys) = start();

      backend.interrupt();
      await pumpEventQueue();

      expect(keys.single.matches(LogicalKey.keyC, ctrl: true), isTrue);
      expect(backend.exitCodes, [0]);
      expect(backend.outputAtExit, contains(EscapeCodes.mainBuffer));
      expect(binding.shouldExit, isTrue);
    });

    test('an exit request handler can cancel and later allow exit', () async {
      final (:binding, :backend, keys: _) = start();
      var response = AppExitResponse.cancel;
      var consulted = 0;
      AppExitResponse handler() {
        consulted++;
        return response;
      }

      binding.addExitRequestHandler(handler);
      backend.interrupt();
      await pumpEventQueue();
      expect(consulted, 1);
      expect(backend.exitCodes, isEmpty);

      response = AppExitResponse.exit;
      backend.interrupt();
      await pumpEventQueue();
      expect(consulted, 2);
      expect(backend.exitCodes, [0]);
    });

    test('handlers run in order until the first cancel', () async {
      final (:binding, :backend, keys: _) = start();
      final calls = <String>[];
      binding
        ..addExitRequestHandler(() {
          calls.add('first');
          return AppExitResponse.exit;
        })
        ..addExitRequestHandler(() {
          calls.add('second');
          return AppExitResponse.cancel;
        })
        ..addExitRequestHandler(() {
          calls.add('third');
          return AppExitResponse.exit;
        });

      backend.interrupt();
      await pumpEventQueue();

      expect(calls, ['first', 'second']);
      expect(backend.exitCodes, isEmpty);
    });

    test('removed handlers are no longer consulted', () async {
      final (:binding, :backend, keys: _) = start();
      AppExitResponse cancel() => AppExitResponse.cancel;
      binding
        ..addExitRequestHandler(cancel)
        ..removeExitRequestHandler(cancel);

      backend.interrupt();
      await pumpEventQueue();

      expect(backend.exitCodes, [0]);
    });

    test('a throwing handler is reported and does not trap the user', () async {
      final errors = <Object>[];
      final (:binding, :backend, keys: _) = start(errors: errors);
      binding.addExitRequestHandler(() => throw StateError('handler failed'));

      backend.interrupt();
      await pumpEventQueue();

      expect(errors, [isStateError]);
      expect(backend.exitCodes, [0]);
    });

    test('a widget veto does not consult exit request handlers', () async {
      final (:binding, :backend, keys: _) = start(handleCtrlC: true);
      var consulted = 0;
      binding.addExitRequestHandler(() {
        consulted++;
        return AppExitResponse.exit;
      });

      backend.interrupt();
      await pumpEventQueue();

      expect(consulted, 0);
      expect(backend.exitCodes, isEmpty);
    });
  });
}

final class _SignalBackend extends TerminalBackend
    implements TerminalTerminationSource {
  final _interrupts = StreamController<void>.broadcast();
  final _terminations = StreamController<void>.broadcast();
  final output = StringBuffer();
  final exitCodes = <int>[];
  bool rawMode = false;
  bool disposed = false;
  String? outputAtExit;
  bool? rawModeAtExit;
  bool? disposedAtExit;

  void interrupt() => _interrupts.add(null);

  void terminate() => _terminations.add(null);

  @override
  void writeRaw(String data) => output.write(data);

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => null;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => _interrupts.stream;

  @override
  Stream<void> get terminationStream => _terminations.stream;

  @override
  void enableRawMode() => rawMode = true;

  @override
  void disableRawMode() => rawMode = false;

  @override
  bool get isAvailable => !disposed;

  @override
  void requestExit([int exitCode = 0]) {
    exitCodes.add(exitCode);
    outputAtExit = output.toString();
    rawModeAtExit = rawMode;
    disposedAtExit = disposed;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_interrupts.close());
    unawaited(_terminations.close());
  }
}
