import 'dart:async';
import 'dart:io';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test(
    'controller replacement detaches the previous terminal output',
    () async {
      final previous = _ObservedController();
      final current = _ObservedController();
      addTearDown(previous.dispose);
      addTearDown(current.dispose);
      await previous.startReady();
      await current.startReady();

      await testCinder('replace terminal controller', (tester) async {
        await tester.pumpWidget(_TerminalHost(previous));
        await previous.emit('BEFORE');
        await tester.pump();
        expect(tester.terminalState.containsText('INPUT:BEFORE'), isTrue);

        tester.findState<_TerminalHostState>().replace(current);
        await tester.pump();
        expect(tester.terminalState.containsText('INPUT:BEFORE'), isTrue);
        await previous.emit('STALE');
        await tester.pump();
        expect(tester.terminalState.containsText('INPUT:STALE'), isFalse);
        expect(previous.outputCallbacks, hasLength(0));

        await current.emit('CURRENT');
        await tester.pump();
        expect(tester.terminalState.containsText('INPUT:CURRENT'), isTrue);
        expect(current.outputCallbacks, hasLength(1));

        await tester.pumpWidget(const SizedBox());
        expect(current.outputCallbacks, hasLength(0));
        final deliveries = current.deliveries;
        await current.emit('UNMOUNTED');
        expect(current.deliveries, deliveries);
      }, size: const Size(80, 24));
    },
  );

  test(
    'repeated terminal mounts retain only the active output callback',
    () async {
      final controller = _ObservedController();
      addTearDown(controller.dispose);
      await controller.startReady();

      await testCinder('terminal remounts', (tester) async {
        for (var i = 0; i < 4; i++) {
          await tester.pumpWidget(
            TerminalXterm(controller: controller, autoStart: false),
          );
          await controller.emit('MOUNTED$i');
          await tester.pump();
          expect(tester.terminalState.containsText('INPUT:MOUNTED$i'), isTrue);
          expect(controller.outputCallbacks, hasLength(1));

          await tester.pumpWidget(const SizedBox());
          expect(controller.outputCallbacks, hasLength(0));
          final deliveries = controller.deliveries;
          await controller.emit('DETACHED$i');
          expect(controller.deliveries, deliveries);
        }
      }, size: const Size(80, 24));
    },
  );
}

class _TerminalHost extends StatefulWidget {
  final PtyController initialController;
  const _TerminalHost(this.initialController);

  @override
  State<_TerminalHost> createState() => _TerminalHostState();
}

class _TerminalHostState extends State<_TerminalHost> {
  late PtyController _controller = widget.initialController;

  void replace(PtyController controller) =>
      setState(() => _controller = controller);

  @override
  Widget build(BuildContext context) =>
      TerminalXterm(controller: _controller, autoStart: false);
}

/// Observes actual callback delivery while retaining the real controller,
/// native child, output decoding, and terminal rendering paths.
class _ObservedController extends PtyController {
  final outputCallbacks =
      <({void Function(String) callback, void Function(String) observer})>[];
  int deliveries = 0;
  Completer<void>? _received;
  String _expected = '';
  String _output = '';

  _ObservedController()
    : super(
        command: Platform.resolvedExecutable,
        arguments: [
          File('test/process/fixtures/pty_process.dart').absolute.path,
          'interactive',
        ],
      ) {
    super.addOutputCallback((data) {
      _output += data;
      if (_output.contains(_expected) && !(_received?.isCompleted ?? true)) {
        _received!.complete();
      }
    });
  }

  Future<void> startReady() async {
    _expected = 'READY:';
    _received = Completer<void>();
    await start(columns: 80, rows: 24);
    await _received!.future.timeout(const Duration(seconds: 10));
  }

  Future<void> emit(String token) async {
    _output = '';
    _expected = 'INPUT:$token';
    _received = Completer<void>();
    write('$token${Platform.isWindows ? '\r' : '\n'}');
    await _received!.future.timeout(const Duration(seconds: 10));
  }

  @override
  void addOutputCallback(void Function(String) callback) {
    void observer(String data) {
      deliveries++;
      callback(data);
    }

    outputCallbacks.add((callback: callback, observer: observer));
    super.addOutputCallback(observer);
  }

  @override
  void removeOutputCallback(void Function(String) callback) {
    final index = outputCallbacks.indexWhere(
      (entry) => entry.callback == callback,
    );
    if (index < 0) return;
    super.removeOutputCallback(outputCallbacks.removeAt(index).observer);
  }
}
