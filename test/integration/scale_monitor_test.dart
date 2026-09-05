import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

import '../../example/scale_monitor.dart';

void main() {
  test('search requested by a completion listener is not stranded', () async {
    final model = ScaleMonitorModel(recordCount: 1000);
    Future<void>? followup;
    model.addListener(() {
      if (model.appliedQuery == 'payment' && followup == null) {
        followup = model.search('worker');
      }
    });
    await model.search('payment');
    await followup;
    expect(model.appliedQuery, 'worker');
    expect(model.pendingSearchCount, 0);
    expect(model.recordAt(0).id, 3);
    await model.dispose();
  });

  test('native Enter submits a query at the input cap', () async {
    final model = ScaleMonitorModel(recordCount: 1000);
    await testCinder('native text commit', (tester) async {
      await tester.pumpWidget(ScaleMonitor(model: model));
      await tester.sendKey(LogicalKey.slash);
      await tester.sendKeyEvent(
        KeyboardEvent(
          logicalKey: const LogicalKey(0x1f680, 'text-input'),
          character: '🚀' * 20000,
        ),
      );
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.enter, character: '\n'),
      );
      await model.searchSettled;
      expect(model.appliedQuery.length, 256);
      expect(model.visibleCount, 0);
    }, size: const Size(100, 24));
  });

  test('focus takes effect for the rest of one physical input burst', () async {
    final model = ScaleMonitorModel(recordCount: 1000);
    await testCinder('search burst', (tester) async {
      await tester.pumpWidget(ScaleMonitor(model: model));
      final binding = CinderTestBinding.instance;
      binding.enterText('/payment');
      binding.sendKeyboardEvent(
        const KeyboardEvent(logicalKey: LogicalKey.enter),
      );
      await tester.pump();
      await model.searchSettled;
      await tester.pump();
      expect(model.appliedQuery, 'payment');
      expect(model.visibleCount, 250);
      binding.enterText('/worker');
      binding.sendKeyboardEvent(
        const KeyboardEvent(logicalKey: LogicalKey.enter),
      );
      binding.enterText('l');
      await tester.pump();
      expect(model.showLive, isTrue);
      await model.searchSettled;
    }, size: const Size(100, 24));
  });

  test(
    'row construction stays within viewport budget at 100k records',
    () async {
      for (final count in [1000, 100000]) {
        final model = ScaleMonitorModel(recordCount: count);
        await testCinder('archive $count', (tester) async {
          await tester.pumpWidget(ScaleMonitor(model: model));
          expect(model.rowBuildCount, lessThanOrEqualTo(40));
          expect(tester.terminalState.containsText('東京'), isTrue);
          final before = model.rowBuildCount;
          await tester.sendKey(LogicalKey.end);
          await tester.pump();
          expect(model.selectedRecord?.id, count - 1);
          expect(model.rowBuildCount - before, lessThanOrEqualTo(80));
          expect(tester.terminalState.containsText('${count - 1}'), isTrue);
          expect(
            tester.findAllWidgets<ScaleLogRow>().length,
            lessThanOrEqualTo(40),
          );
        }, size: const Size(100, 24));
        expect(model.isDisposed, isTrue);
      }
    },
  );

  test(
    'stream evicts oldest records and coalesces a burst into one update',
    () async {
      final model = ScaleMonitorModel(recordCount: 1000, historyLimit: 32);
      var updates = 0;
      model.addListener(() => updates++);
      for (var i = 0; i < 10000; i++) {
        model.ingest(1);
      }
      expect(updates, 0);
      await Future<void>.delayed(Duration.zero);
      expect(updates, 1);
      expect(model.liveCount, 32);
      expect(model.liveRecordAt(0).id, 10968);
      expect(model.liveRecordAt(31).id, 10999);
      expect(model.droppedRecords, 9968);
      await model.dispose();
    },
  );

  test(
    'search replaces stale work and retains at most one active job',
    () async {
      final model = ScaleMonitorModel(recordCount: 100000);
      final first = model.search('東京');
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 100; i++) {
        model.search('no-such-record-$i');
      }
      final last = model.search('payment');
      expect(model.activeSearchCount, 1);
      expect(model.pendingSearchCount, 1);
      await Future.wait([first, last]);
      expect(model.appliedQuery, 'payment');
      expect(model.visibleCount, 25000);
      expect(model.recordAt(0).id, 1);
      expect(model.recordAt(24999).id, 99997);
      expect(model.maxActiveSearchCount, 1);
      expect(model.searchCancelledCount, greaterThan(0));
      expect(model.searchRecordsExamined, lessThan(101000));
      expect(model.activeSearchCount, 0);
      await model.dispose();
    },
  );

  test(
    'bounded query preserves Unicode and Escape cancels without stale commit',
    () async {
      final model = ScaleMonitorModel(recordCount: 100000);
      await model.search('payment');
      final search = model.search('🚀' * 100000);
      expect(model.query.length, lessThanOrEqualTo(256));
      expect(model.query.runes.every((rune) => rune == 0x1f680), isTrue);
      model.cancelSearch();
      await search;
      expect(model.appliedQuery, 'payment');
      expect(model.visibleCount, 25000);
      expect(model.searchCancelledCount, greaterThan(0));
      await model.dispose();
    },
  );

  test(
    'dispose stops producer, cancels search and releases record storage',
    () async {
      final model = ScaleMonitorModel(recordCount: 100000, historyLimit: 32);
      model.startStreaming(interval: const Duration(milliseconds: 1), burst: 8);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(model.ingestedRecords, greaterThan(0));
      final search = model.search('東京');
      final before = model.ingestedRecords;
      var updates = 0;
      model.addListener(() => updates++);
      await model.dispose();
      await search;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(model.ingestedRecords, before);
      expect(model.liveCount, 0);
      expect(model.retainedArchiveCount, 0);
      expect(model.activeSearchCount, 0);
      expect(model.isStreaming, isFalse);
      expect(updates, 0);
      await model.dispose();
    },
  );

  test(
    'keyboard search, long paste, live view and paused stream remain usable',
    () async {
      final model = ScaleMonitorModel(recordCount: 1000);
      await testCinder('input lifecycle', (tester) async {
        await tester.pumpWidget(ScaleMonitor(model: model));
        await tester.sendKeyEvent(
          const KeyboardEvent(logicalKey: LogicalKey.slash, character: '/'),
        );
        await tester.enterText('payment');
        await tester.sendEnter();
        await model.searchSettled;
        await tester.pump();
        expect(model.visibleCount, 250);
        expect(model.selectedRecord?.id, 1);
        await tester.sendKeyEvent(
          const KeyboardEvent(logicalKey: LogicalKey.slash, character: '/'),
        );
        ClipboardManager.copy('🚀' * 100000);
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyV,
            modifiers: ModifierKeys(ctrl: true),
          ),
        );
        expect(
          tester.findWidget<TextField>()!.controller!.text.length,
          lessThanOrEqualTo(256),
        );
        await tester.sendKeyEvent(
          KeyboardEvent(
            logicalKey: const LogicalKey(0x1f680, 'text-input'),
            character: '🚀' * 100000,
          ),
        );
        expect(
          tester.findWidget<TextField>()!.controller!.text.length,
          lessThanOrEqualTo(256),
        );
        await tester.sendEscape();
        model.ingest(5);
        await tester.sendKey(LogicalKey.keyL);
        await tester.pump();
        expect(model.showLive, isTrue);
        expect(tester.terminalState.containsText('LIVE'), isTrue);
        await tester.pumpWidget(const Text('closed'));
        await model.dispose();
        expect(model.isDisposed, isTrue);
      }, size: const Size(100, 24));
    },
  );
}
