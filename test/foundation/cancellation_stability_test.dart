import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('CinderTaskScope stability', () {
    test('retains a bounded completed-task history', () async {
      final scope = CinderTaskScope(historyLimit: 3);

      for (var index = 0; index < 10; index++) {
        expect(
          await scope.run<int>((_) => index, label: 'job-$index').future,
          index,
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(scope.pendingTaskCount, 0);
      expect(scope.startedTaskCount, 10);
      expect(scope.completedTaskCount, 10);
      expect(scope.history, hasLength(3));
      expect(scope.history.map((entry) => entry.label),
          <String>['job-7', 'job-8', 'job-9']);
      expect(
        scope.history.every(
          (entry) => entry.state == CinderTaskState.succeeded,
        ),
        isTrue,
      );
    });

    test('records failure and cancellation independently', () async {
      final scope = CinderTaskScope();
      final failed = scope.run<void>((_) => throw StateError('boom'));
      await expectLater(failed.future, throwsStateError);

      final cancelled = scope.run<void>((token) async {
        await token.whenCancelled;
        token.throwIfCancelled();
      });
      cancelled.cancel('stop');
      await expectLater(
          cancelled.future, throwsA(isA<CancellationException>()));
      await Future<void>.delayed(Duration.zero);

      expect(failed.state, CinderTaskState.failed);
      expect(cancelled.state, CinderTaskState.cancelled);
      expect(
          scope.history.map((entry) => entry.state),
          containsAll(<CinderTaskState>[
            CinderTaskState.failed,
            CinderTaskState.cancelled,
          ]));
      await scope.dispose();
    });

    test('cancellation listeners may release owned resources immediately',
        () async {
      final scope = CinderTaskScope();
      final timer = Timer(const Duration(minutes: 1), () {});
      final task = scope.run<void>((token) async {
        token.addListener(timer.cancel);
        await token.whenCancelled;
      });

      task.cancel('screen closed');
      await task.future;

      expect(timer.isActive, isFalse);
      await scope.dispose();
    });
  });
}
