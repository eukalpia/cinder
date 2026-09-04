import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('CancellationToken', () {
    test('notifies listeners once and preserves the reason', () async {
      final source = CancellationTokenSource();
      var notifications = 0;
      source.token.addListener(() => notifications++);

      source.cancel('shutdown');
      source.cancel('ignored');

      await source.token.whenCancelled;
      expect(source.token.isCancelled, isTrue);
      expect(source.token.reason, 'shutdown');
      expect(notifications, 1);
      expect(
        source.token.throwIfCancelled,
        throwsA(
          isA<CancellationException>().having(
            (error) => error.reason,
            'reason',
            'shutdown',
          ),
        ),
      );
    });

    test('invokes listeners registered after cancellation', () {
      final source = CancellationTokenSource()..cancel();
      var notified = false;

      source.token.addListener(() => notified = true);

      expect(notified, isTrue);
    });
  });

  group('CinderTaskScope', () {
    test('cancels and awaits owned work during disposal', () async {
      final scope = CinderTaskScope();
      final cleanupComplete = Completer<void>();

      final task = scope.run<void>((token) async {
        await token.whenCancelled;
        try {
          token.throwIfCancelled();
        } finally {
          cleanupComplete.complete();
        }
      });

      final disposeFuture = scope.dispose('screen closed');

      await expectLater(task.future, throwsA(isA<CancellationException>()));
      await disposeFuture;
      await cleanupComplete.future;

      expect(scope.isDisposed, isTrue);
      expect(scope.pendingTaskCount, 0);
    });

    test('keeps successful tasks distinct from cancelled tasks', () async {
      final scope = CinderTaskScope();
      final task = scope.run<int>((_) => 42);

      expect(await task.future, 42);
      await Future<void>.delayed(Duration.zero);

      expect(task.isCancelled, isFalse);
      expect(scope.pendingTaskCount, 0);
      await scope.dispose();
    });

    test('rejects new work after disposal', () async {
      final scope = CinderTaskScope();
      await scope.dispose();

      expect(() => scope.run<void>((_) {}), throwsStateError);
    });

    test('concurrent disposal waits for task cleanup', () async {
      final scope = CinderTaskScope();
      final release = Completer<void>();
      final task = scope.run<void>((token) async {
        await token.whenCancelled;
        await release.future;
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
        await Future.wait([task.future, firstDisposal, secondDisposal]);
      }
      expect(scope.pendingTaskCount, 0);
    });

    test(
      'disposal inside an operation cancels and waits for that task',
      () async {
        final scope = CinderTaskScope();
        final release = Completer<void>();
        late Future<void> disposal;
        final task = scope.run<void>((token) {
          disposal = scope.dispose();
          return release.future;
        });
        var disposalFinished = false;
        final observedDisposal = disposal.then((_) => disposalFinished = true);
        await Future<void>.delayed(Duration.zero);

        try {
          expect(task.isCancelled, isTrue);
          expect(disposalFinished, isFalse);
        } finally {
          release.complete();
          await Future.wait([task.future, observedDisposal]);
        }
        expect(scope.pendingTaskCount, 0);
      },
    );
  });
}
