import '../components/focus.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../size.dart';

/// One serializable node in a diagnostics tree.
class DiagnosticsNodeData {
  DiagnosticsNodeData({
    required this.name,
    this.properties = const <String, Object?>{},
    List<DiagnosticsNodeData> children = const <DiagnosticsNodeData>[],
  }) : children = List<DiagnosticsNodeData>.unmodifiable(children);

  final String name;
  final Map<String, Object?> properties;
  final List<DiagnosticsNodeData> children;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        if (properties.isNotEmpty) 'properties': properties,
        if (children.isNotEmpty)
          'children': children.map((child) => child.toJson()).toList(),
      };

  String format({int depth = 0}) {
    final prefix = '  ' * depth;
    final details = properties.isEmpty
        ? ''
        : ' ${properties.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    return <String>[
      '$prefix$name$details',
      for (final child in children) child.format(depth: depth + 1),
    ].join('\n');
  }
}

/// A point-in-time view of widget, render, focus, semantics, and frame state.
class CinderDiagnosticsSnapshot {
  const CinderDiagnosticsSnapshot({
    required this.capturedAt,
    required this.widgetTree,
    required this.renderTrees,
    required this.focusTree,
    required this.semantics,
    required this.frameMetrics,
  });

  final DateTime capturedAt;
  final DiagnosticsNodeData? widgetTree;
  final List<DiagnosticsNodeData> renderTrees;
  final DiagnosticsNodeData focusTree;
  final SemanticsSnapshot semantics;
  final Map<String, Object?> frameMetrics;

  Map<String, Object?> toJson() => <String, Object?>{
        'capturedAt': capturedAt.toIso8601String(),
        if (widgetTree != null) 'widgetTree': widgetTree!.toJson(),
        'renderTrees': renderTrees.map((node) => node.toJson()).toList(),
        'focusTree': focusTree.toJson(),
        'semantics': semantics.toJson()['semantics'],
        'frameMetrics': frameMetrics,
      };
}

/// Collects development diagnostics without changing rendering semantics.
abstract final class CinderDiagnostics {
  static CinderDiagnosticsSnapshot capture([CinderBinding? binding]) {
    final effectiveBinding = binding ?? CinderBinding.instance;
    final root = effectiveBinding.rootElement;
    final renderRoots = <RenderObject>[];
    if (root != null) _collectRenderRoots(root, renderRoots, false);

    return CinderDiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      widgetTree: root == null ? null : _captureElement(root),
      renderTrees: renderRoots.map(_captureRenderObject).toList(),
      focusTree: _captureFocusNode(FocusManager.instance.rootScope),
      semantics: SemanticsSnapshot.capture(root),
      frameMetrics: _readFrameMetrics(effectiveBinding),
    );
  }

  static DiagnosticsNodeData _captureElement(Element element) {
    final children = <DiagnosticsNodeData>[];
    element.visitChildren((child) => children.add(_captureElement(child)));
    final renderObject = element.renderObject;
    return DiagnosticsNodeData(
      name: element.widget.runtimeType.toString(),
      properties: <String, Object?>{
        'element': element.runtimeType.toString(),
        'depth': element.depth,
        'dirty': element.dirty,
        if (element.widget.key != null) 'key': element.widget.key.toString(),
        if (renderObject != null)
          'renderObject': renderObject.runtimeType.toString(),
      },
      children: children,
    );
  }

  static void _collectRenderRoots(
    Element element,
    List<RenderObject> output,
    bool insideRenderSubtree,
  ) {
    final current =
        element is RenderObjectElement ? element.renderObject : null;
    final isInside = insideRenderSubtree || current != null;
    if (current != null && !insideRenderSubtree) output.add(current);
    element.visitChildren(
      (child) => _collectRenderRoots(child, output, isInside),
    );
  }

  static DiagnosticsNodeData _captureRenderObject(RenderObject renderObject) {
    final children = <DiagnosticsNodeData>[];
    renderObject.visitChildren(
      (child) => children.add(_captureRenderObject(child)),
    );
    final size = _safeSize(renderObject);
    return DiagnosticsNodeData(
      name: renderObject.runtimeType.toString(),
      properties: <String, Object?>{
        'needsLayout': renderObject.needsLayout,
        'needsPaint': renderObject.needsPaint,
        if (size != null) 'size': '${size.width}x${size.height}',
        if (renderObject.selectionId != null)
          'selectionId': renderObject.selectionId.toString(),
      },
      children: children,
    );
  }

  static Size? _safeSize(RenderObject object) {
    try {
      return object.size;
    } catch (_) {
      return null;
    }
  }

  static DiagnosticsNodeData _captureFocusNode(FocusNode node) {
    final children = node is FocusScopeNode
        ? node.children.map(_captureFocusNode).toList()
        : const <DiagnosticsNodeData>[];
    return DiagnosticsNodeData(
      name: node.debugLabel ?? node.runtimeType.toString(),
      properties: <String, Object?>{
        'attached': node.attached,
        'focused': node.hasFocus,
        'primary': node.hasPrimaryFocus,
        'canRequestFocus': node.canRequestFocus,
        'skipTraversal': node.skipTraversal,
      },
      children: children,
    );
  }

  static Map<String, Object?> _readFrameMetrics(CinderBinding binding) {
    try {
      final dynamic terminalBinding = binding;
      return <String, Object?>{
        'comparedCells': terminalBinding.lastComparedCells as int,
        'writtenCells': terminalBinding.lastWrittenCells as int,
        'ansiRuns': terminalBinding.lastAnsiRuns as int,
        'outputCodeUnits': terminalBinding.lastOutputCodeUnits as int,
        'partialPaintBoundaries':
            terminalBinding.lastPartialPaintBoundaries as int,
      };
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}
