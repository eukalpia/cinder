import 'dart:async';
import 'dart:convert';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  late _SlowBackend backend;
  late TerminalBinding binding;
  late _CounterState state;

  setUp(() {
    backend = _SlowBackend();
    binding = TerminalBinding(
      Terminal(backend),
      capabilities: const TerminalCapabilities(),
    )..enableFrameRateLimiting = false;
    binding.initialize();
    binding.attachRootWidget(_Counter((value) => state = value));
    binding.scheduleFrame();
  });
  tearDown(() {
    binding.shutdown();
    backend.finish();
    CinderBinding.resetInstance();
  });

  Future<void> nextEvent() => Future<void>.delayed(Duration.zero);

  test(
    'slow output coalesces state changes into the next drained frame',
    () async {
      await nextEvent();
      expect(backend.drains, 1);
      final firstFrame = backend.writes.length;
      for (var index = 1; index <= 1000; index++) {
        state.update(index);
      }
      await nextEvent();
      await nextEvent();
      expect(backend.writes.length, firstFrame);
      expect(state.builds, 1);

      backend.finish();
      await nextEvent();
      await nextEvent();
      expect(state.builds, 2);
      expect(backend.writes.last, contains('1000'));
      expect(backend.drains, 2);
    },
  );

  test('input is dispatched while a frame waits for output', () async {
    await nextEvent();
    final received = <InputEvent>[];
    final subscription = binding.inputEvents.listen(received.add);
    backend.input.add([0x78]);
    await nextEvent();
    expect(
      received.whereType<KeyboardInputEvent>().single.event.character,
      'x',
    );
    await subscription.cancel();
  });

  test('delayed bracketed paste remains one paste event', () async {
    await nextEvent();
    final received = <InputEvent>[];
    final subscription = binding.inputEvents.listen(received.add);
    backend.input.add(utf8.encode('\x1b[200~hello'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(received, hasLength(0));
    backend.input.add(utf8.encode('世界\x1b[201~'));
    await nextEvent();
    expect(received, hasLength(1));
    expect(received.single, isA<PasteInputEvent>());
    expect((received.single as PasteInputEvent).text, 'hello世界');
    await subscription.cancel();
  });

  test('legacy input excludes OSC while preserving pasted OSC text', () async {
    await nextEvent();
    final raw = <String>[];
    final subscription = binding.input.listen(raw.add);
    backend.input.add(utf8.encode('\x1b]11;rgb:ffff/0000/0000\x07x'));
    await nextEvent();
    expect(raw.join(), 'x');
    raw.clear();
    const paste = '\x1b[200~before\x1b]2;title\x07after\x1b[201~';
    backend.input.add(utf8.encode(paste));
    await nextEvent();
    expect(raw.join(), paste);
    await subscription.cancel();
  });

  test('delayed UTF-8 and CSI fragments preserve their events', () async {
    await nextEvent();
    final received = <InputEvent>[];
    final subscription = binding.inputEvents.listen(received.add);
    final character = utf8.encode('界');
    backend.input.add(character.sublist(0, 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    backend.input.add([...character.sublist(1), ...utf8.encode('\x1b[1;')]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    backend.input.add(utf8.encode('5D'));
    await nextEvent();
    final keys = received.cast<KeyboardInputEvent>();
    expect(keys.map((event) => event.event.logicalKey), [
      LogicalKey.fromCharacter('界'),
      LogicalKey.arrowLeft,
    ]);
    expect(keys.last.event.isControlPressed, isTrue);
    await subscription.cancel();
  });

  test(
    'OSC content inside bracketed paste cannot change the viewport',
    () async {
      await nextEvent();
      final received = <InputEvent>[];
      final reports = <String>[];
      final subscription = binding.inputEvents.listen(received.add);
      final oscSubscription = binding.oscEvents.listen(reports.add);
      const text = 'before\x1b]9999;99;33\x07after';
      backend.input.add(utf8.encode('\x1b[200~$text\x1b[201~'));
      await nextEvent();
      expect(reports, hasLength(0));
      expect(binding.terminal.size, const Size(40, 5));
      expect((received.single as PasteInputEvent).text, text);
      await subscription.cancel();
      await oscSubscription.cancel();
    },
  );

  test('OSC replies accept every packet split and both terminators', () async {
    await nextEvent();
    final keys = <KeyboardEvent>[];
    final reports = <String>[];
    final subscription = binding.keyboardEvents.listen(keys.add);
    final oscSubscription = binding.oscEvents.listen(reports.add);
    for (final terminator in ['\x07', '\x1b\\']) {
      final bytes = utf8.encode('\x1b]11;rgb:ffff/0000/0000${terminator}x');
      for (var split = 0; split <= bytes.length; split++) {
        keys.clear();
        reports.clear();
        backend.input.add(bytes.sublist(0, split));
        await nextEvent();
        backend.input.add(bytes.sublist(split));
        await nextEvent();
        expect(reports, ['11;rgb:ffff/0000/0000'], reason: 'split $split');
        expect(keys.map((key) => key.character), ['x'], reason: 'split $split');
      }
    }
    await subscription.cancel();
    await oscSubscription.cancel();
  });

  test('invalid OSC resize dimensions cannot expand the viewport', () async {
    await nextEvent();
    // The pending output drain prevents an invalid size from allocating a
    // frame before the assertion, including on the unfixed implementation.
    for (final dimensions in ['5000;5000', '0;24', '-1;24', '2048;2048']) {
      backend.input.add(utf8.encode('\x1b]9999;$dimensions\x07'));
      await nextEvent();
      expect(binding.terminal.size, const Size(40, 5), reason: dimensions);
      expect(backend.sizeNotifications, hasLength(0), reason: dimensions);
    }
    backend.input.add(utf8.encode('\x1b]9999;120;40\x07'));
    await nextEvent();
    expect(binding.terminal.size, const Size(120, 40));
    expect(backend.sizeNotifications, [const Size(120, 40)]);
  });

  test(
    'resize while blocked renders only the latest viewport after drain',
    () async {
      await nextEvent();
      final count = backend.writes.length;
      backend.resize.add(const Size(30, 5));
      backend.resize.add(const Size(20, 3));
      await nextEvent();
      await nextEvent();
      expect(backend.writes.length, count);
      backend.finish();
      await nextEvent();
      await nextEvent();
      expect(binding.terminal.size, const Size(20, 3));
      expect(backend.drains, 2);
    },
  );

  test('large input bursts yield to timers without losing events', () async {
    await nextEvent();
    var received = 0;
    final allReceived = Completer<void>();
    final subscription = binding.inputEvents.listen((_) {
      if (++received == 20000) allReceived.complete();
    });
    backend.input.add(List<int>.filled(20000, 0x78));
    await nextEvent();
    expect(received, greaterThan(0));
    expect(received, lessThan(20000));
    await allReceived.future.timeout(const Duration(seconds: 5));
    await subscription.cancel();
  });

  test('expensive input handlers yield before a small burst finishes', () async {
    await nextEvent();
    var handled = 0;
    final yieldedAfter = Completer<int>();
    final allHandled = Completer<void>();
    binding.inputRouter.add(InputPhase.capture, (_, __) {
      handled++;
      if (handled == 1) {
        Timer.run(() => yieldedAfter.complete(handled));
        // Model synchronous work in an application callback. Only the first
        // callback blocks, so this exercises fairness without a timing race or
        // hundreds of slow handlers.
        final work = Stopwatch()..start();
        while (work.elapsedMilliseconds < 20) {}
      }
      if (handled == 32) allHandled.complete();
      return InputDisposition.handled;
    });
    backend.input.add(List<int>.filled(32, 0x78));
    expect(await yieldedAfter.future, lessThan(32));
    await allHandled.future.timeout(const Duration(seconds: 5));
    expect(handled, 32);
  });

  test(
    'queued single-key packets yield to timers without losing order',
    () async {
      await nextEvent();
      final received = <String>[];
      final yieldedAfter = Completer<int>();
      final allHandled = Completer<void>();
      final keys = List.generate(
        16,
        (index) => String.fromCharCode(0x61 + index),
      );
      binding.inputRouter.add(InputPhase.capture, (event, _) {
        received.add((event as KeyboardInputEvent).event.character!);
        if (received.length == 1) {
          Timer.run(() => yieldedAfter.complete(received.length));
        }
        final work = Stopwatch()..start();
        while (work.elapsedMilliseconds < 2) {}
        if (received.length == keys.length) allHandled.complete();
        return InputDisposition.handled;
      });
      for (final key in keys) {
        backend.input.add(utf8.encode(key));
      }
      expect(await yieldedAfter.future, lessThan(keys.length));
      await allHandled.future.timeout(const Duration(seconds: 5));
      expect(received, keys);
    },
  );

  test('a timer scheduled inside a frame still waits for output', () async {
    var nextAnimation = 0;
    binding.scheduleFrameCallback((_) {
      binding.scheduleFrameCallback((_) => nextAnimation++);
    });
    await nextEvent();
    await nextEvent();
    expect(nextAnimation, 0);
    backend.finish();
    await nextEvent();
    await nextEvent();
    expect(nextAnimation, 1);
  });

  test('unknown escape floods also yield before the final key', () async {
    await nextEvent();
    final received = <InputEvent>[];
    final complete = Completer<void>();
    final subscription = binding.inputEvents.listen((event) {
      received.add(event);
      complete.complete();
    });
    backend.input.add(utf8.encode('${'\x1b[2A' * 20000}x'));
    await nextEvent();
    expect(received, hasLength(0));
    await complete.future.timeout(const Duration(seconds: 5));
    expect((received.single as KeyboardInputEvent).event.character, 'x');
    await subscription.cancel();
  });

  test('shutdown inside an input handler stops the remaining burst', () async {
    await nextEvent();
    var handled = 0;
    binding.inputRouter.add(InputPhase.capture, (_, __) {
      handled++;
      binding.shutdown();
      return InputDisposition.stopPropagation;
    });
    backend.input.add(List<int>.filled(20000, 0x78));
    await nextEvent();
    await nextEvent();
    expect(handled, 1);
    expect(backend.disposed, isTrue);
  });

  test(
    'a failed handler preserves its error and resumes paused input',
    () async {
      binding.shutdown();
      backend.finish();
      backend = _SlowBackend();
      final errorSeen = Completer<void>();
      final allHandled = Completer<void>();
      final failure = StateError('one intentional handler failure');
      final errors = <Object>[];
      final received = <String>[];
      var failed = false;
      // The input subscription belongs to this zone, so its original application
      // error stays observable while the binding recovers its paused source.
      runZonedGuarded(
        () {
          binding = TerminalBinding(
            Terminal(backend),
            capabilities: const TerminalCapabilities(),
          )..initialize();
          binding.inputRouter.add(InputPhase.capture, (event, _) {
            received.add((event as KeyboardInputEvent).event.character!);
            if (backend.input.isPaused && !failed) {
              failed = true;
              throw failure;
            }
            if (received.length == 1025) allHandled.complete();
            return InputDisposition.handled;
          });
          backend.input.add(List<int>.filled(1024, 0x78));
        },
        (error, _) {
          errors.add(error);
          if (!errorSeen.isCompleted) errorSeen.complete();
        },
      );
      await errorSeen.future.timeout(const Duration(seconds: 5));
      backend.input.add([0x79]);
      await allHandled.future.timeout(const Duration(seconds: 1));
      await nextEvent();
      expect(errors, [same(failure)]);
      expect(received, [...List.filled(1024, 'x'), 'y']);
      expect(backend.input.isPaused, isFalse);
    },
  );

  test('drain completion after shutdown cannot restart rendering', () async {
    await nextEvent();
    state.update(2);
    binding.shutdown();
    final writes = backend.writes.length;
    backend.finish();
    await nextEvent();
    await nextEvent();
    expect(backend.writes.length, writes);
    expect(backend.disposed, isTrue);
    expect(CinderBinding.hasInstance, isFalse);
  });

  test('output failure shuts down and releases resources', () async {
    await nextEvent();
    final errors = <CinderErrorDetails>[];
    final previousHandler = CinderError.onError;
    CinderError.onError = errors.add;
    addTearDown(() => CinderError.onError = previousHandler);
    backend.pending!.completeError(StateError('disconnected'));
    backend.pending = null;
    await nextEvent();
    expect(binding.shouldExit, isTrue);
    expect(backend.disposed, isTrue);
    expect(CinderBinding.hasInstance, isFalse);
    expect(errors.single.exception, isStateError);
  });
}

class _Counter extends StatefulWidget {
  const _Counter(this.onReady);
  final void Function(_CounterState) onReady;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;
  int builds = 0;
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  void update(int next) => setState(() => value = next);
  @override
  Widget build(BuildContext context) {
    builds++;
    return Text('$value');
  }
}

class _SlowBackend extends TerminalBackend implements TerminalOutputDrain {
  final input = StreamController<List<int>>();
  final resize = StreamController<Size>();
  final writes = <String>[];
  final sizeNotifications = <Size>[];
  Completer<void>? pending;
  int drains = 0;
  bool disposed = false;

  @override
  Future<void> drainOutput() {
    expect(pending, isNull, reason: 'Only one output drain may be in flight');
    drains++;
    return (pending = Completer<void>()).future;
  }

  void finish() {
    pending?.complete();
    pending = null;
  }

  @override
  void writeRaw(String data) => writes.add(data);
  @override
  Size getSize() => const Size(40, 5);
  @override
  void notifySizeChanged(Size size) => sizeNotifications.add(size);
  @override
  bool get supportsSize => true;
  @override
  Stream<List<int>> get inputStream => input.stream;
  @override
  Stream<Size> get resizeStream => resize.stream;
  @override
  Stream<void>? get shutdownStream => null;
  @override
  void enableRawMode() {}
  @override
  void disableRawMode() {}
  @override
  bool get isAvailable => !disposed;
  @override
  void requestExit([int exitCode = 0]) {}
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    unawaited(input.close());
    unawaited(resize.close());
  }
}
