import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/backend/sink_output.dart';
import 'package:test/test.dart';

void main() {
  test(
    'control writes during flush drain after the frame in exact order',
    () async {
      final consumer = _BlockedConsumer();
      final sink = IOSink(consumer);
      final output = SinkOutput(sink);
      output.write('frame');
      final first = output.drain();
      await Future<void>.delayed(Duration.zero);
      output.write('restore');
      output.write('cursor');
      final second = output.drain();
      expect(identical(first, second), isTrue);
      expect(utf8.decode(consumer.bytes), 'frame');
      consumer.release();
      await Future<void>.delayed(Duration.zero);
      expect(utf8.decode(consumer.bytes), 'framerestorecursor');
      consumer.release();
      await first;
      await second;
      await sink.close();
    },
  );

  test(
    'sink errors complete the drain and release pending control text',
    () async {
      final consumer = _BlockedConsumer();
      final output = SinkOutput(IOSink(consumer));
      output.write('frame');
      final drain = output.drain();
      final failure = expectLater(drain, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      output.write('cleanup');
      consumer.pending!.completeError(StateError('closed pipe'));
      await failure;
    },
  );
}

class _BlockedConsumer implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  Completer<void>? pending;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    final gate = pending = Completer<void>();
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    await gate.future;
  }

  void release() {
    pending!.complete();
    pending = null;
  }

  @override
  Future<void> close() async {}
}
