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
}
