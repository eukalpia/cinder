import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('disposes resources in reverse registration order', () async {
    final scope = CinderResourceScope();
    final order = <int>[];

    scope
      ..add(() => order.add(1))
      ..add(() async => order.add(2))
      ..add(() => order.add(3));

    await scope.dispose();

    expect(order, <int>[3, 2, 1]);
    expect(scope.isDisposed, isTrue);
    expect(scope.resourceCount, 0);
  });

  test('tracks timers and stream subscriptions', () async {
    final scope = CinderResourceScope();
    final controller = StreamController<int>();
    var eventCount = 0;

    final timer = scope.trackTimer(Timer(const Duration(minutes: 1), () {}));
    final subscription = scope.trackSubscription(
      controller.stream.listen((_) => eventCount++),
    );

    await scope.dispose();
    controller.add(1);
    await Future<void>.delayed(Duration.zero);

    expect(timer.isActive, isFalse);
    expect(eventCount, 0);
    await subscription.cancel();
    await controller.close();
  });

  test('continues cleanup and reports the first failure', () async {
    final scope = CinderResourceScope();
    var finalResourceDisposed = false;

    scope
      ..add(() => finalResourceDisposed = true)
      ..add(() => throw StateError('cleanup failed'));

    await expectLater(scope.dispose(), throwsStateError);
    expect(finalResourceDisposed, isTrue);
  });

  test('rejects resources after disposal', () async {
    final scope = CinderResourceScope();
    await scope.dispose();

    expect(() => scope.add(() {}), throwsStateError);
  });

  test('concurrent disposal waits for the same resource cleanup', () async {
    final scope = CinderResourceScope();
    final release = Completer<void>();
    var cleanupFinished = false;
    scope.add(() async {
      await release.future;
      cleanupFinished = true;
    });

    final firstDisposal = scope.dispose();
    var secondDisposalFinished = false;
    final secondDisposal = scope.dispose().then((_) {
      secondDisposalFinished = true;
    });
    await Future<void>.delayed(Duration.zero);

    try {
      expect(secondDisposalFinished, isFalse);
    } finally {
      release.complete();
      await Future.wait([firstDisposal, secondDisposal]);
    }
    expect(cleanupFinished, isTrue);
  });

  test('concurrent disposal reports the same cleanup failure', () async {
    final scope = CinderResourceScope();
    final release = Completer<void>();
    final error = StateError('cleanup failed');
    scope.add(() async {
      await release.future;
      throw error;
    });

    final firstDisposal = expectLater(scope.dispose(), throwsA(same(error)));
    final secondDisposal = expectLater(scope.dispose(), throwsA(same(error)));
    release.complete();
    await Future.wait([firstDisposal, secondDisposal]);
  });
}
