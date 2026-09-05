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
