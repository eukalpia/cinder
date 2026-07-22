/// Runtime diagnostics configured by [CinderApp].
final class CinderDebugOptions {
  const CinderDebugOptions({
    this.showPerformanceOverlay = false,
    this.showRepaintRegions = false,
    this.showFrameTimings = false,
    this.emitTimelineEvents = false,
    this.detectLayoutThrashing = false,
  });

  /// Shows the built-in performance overlay immediately.
  final bool showPerformanceOverlay;

  /// Highlights repainting render objects.
  final bool showRepaintRegions;

  /// Collects frame timing metrics for programmatic inspection.
  final bool showFrameTimings;

  /// Emits timeline events to Dart DevTools.
  final bool emitTimelineEvents;

  /// Enables diagnostics for repeated layout invalidation in a frame.
  final bool detectLayoutThrashing;

  /// The production default with all diagnostics disabled.
  static const CinderDebugOptions disabled = CinderDebugOptions();

  CinderDebugOptions copyWith({
    bool? showPerformanceOverlay,
    bool? showRepaintRegions,
    bool? showFrameTimings,
    bool? emitTimelineEvents,
    bool? detectLayoutThrashing,
  }) {
    return CinderDebugOptions(
      showPerformanceOverlay:
          showPerformanceOverlay ?? this.showPerformanceOverlay,
      showRepaintRegions: showRepaintRegions ?? this.showRepaintRegions,
      showFrameTimings: showFrameTimings ?? this.showFrameTimings,
      emitTimelineEvents: emitTimelineEvents ?? this.emitTimelineEvents,
      detectLayoutThrashing:
          detectLayoutThrashing ?? this.detectLayoutThrashing,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CinderDebugOptions &&
            showPerformanceOverlay == other.showPerformanceOverlay &&
            showRepaintRegions == other.showRepaintRegions &&
            showFrameTimings == other.showFrameTimings &&
            emitTimelineEvents == other.emitTimelineEvents &&
            detectLayoutThrashing == other.detectLayoutThrashing;
  }

  @override
  int get hashCode => Object.hash(
        showPerformanceOverlay,
        showRepaintRegions,
        showFrameTimings,
        emitTimelineEvents,
        detectLayoutThrashing,
      );
}
