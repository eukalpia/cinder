import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('debug options are disabled by default', () {
    const options = CinderDebugOptions.disabled;

    expect(options.showPerformanceOverlay, isFalse);
    expect(options.showRepaintRegions, isFalse);
    expect(options.showFrameTimings, isFalse);
    expect(options.emitTimelineEvents, isFalse);
    expect(options.detectLayoutThrashing, isFalse);
  });

  test('copyWith preserves unspecified diagnostics', () {
    const options = CinderDebugOptions(
      showFrameTimings: true,
      emitTimelineEvents: true,
    );

    final updated = options.copyWith(showRepaintRegions: true);

    expect(updated.showRepaintRegions, isTrue);
    expect(updated.showFrameTimings, isTrue);
    expect(updated.emitTimelineEvents, isTrue);
    expect(updated, isNot(options));
  });
}
