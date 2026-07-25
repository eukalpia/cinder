import 'dart:convert';

import '../framework/framework.dart';
import '../framework/terminal_canvas.dart';
import '../size.dart';

/// Roles exposed by Cinder's terminal semantics tree.
enum SemanticsRole {
  application,
  window,
  dialog,
  group,
  heading,
  text,
  button,
  checkbox,
  radio,
  switchControl,
  textField,
  link,
  menu,
  menuItem,
  tab,
  tabPanel,
  table,
  row,
  cell,
  image,
  progressIndicator,
  status,
}

/// Immutable accessibility and plain-output metadata.
class SemanticsProperties {
  const SemanticsProperties({
    required this.role,
    this.label,
    this.value,
    this.hint,
    this.enabled,
    this.focused,
    this.selected,
    this.checked,
    this.expanded,
    this.readOnly,
    this.hidden = false,
    this.sortKey,
  });

  final SemanticsRole role;
  final String? label;
  final String? value;
  final String? hint;
  final bool? enabled;
  final bool? focused;
  final bool? selected;
  final bool? checked;
  final bool? expanded;
  final bool? readOnly;
  final bool hidden;
  final double? sortKey;

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role.name,
        if (label != null) 'label': label,
        if (value != null) 'value': value,
        if (hint != null) 'hint': hint,
        if (enabled != null) 'enabled': enabled,
        if (focused != null) 'focused': focused,
        if (selected != null) 'selected': selected,
        if (checked != null) 'checked': checked,
        if (expanded != null) 'expanded': expanded,
        if (readOnly != null) 'readOnly': readOnly,
      };
}

/// Annotates a widget subtree for accessibility, diagnostics, and plain output.
class Semantics extends SingleChildRenderObjectWidget {
  const Semantics({super.key, required this.properties, super.child});

  final SemanticsProperties properties;

  @override
  RenderSemantics createRenderObject(BuildContext context) {
    return RenderSemantics(properties);
  }

  @override
  void updateRenderObject(BuildContext context, RenderSemantics renderObject) {
    renderObject.properties = properties;
  }
}

/// Render-tree anchor for semantic metadata.
class RenderSemantics extends RenderObject
    with RenderObjectWithChildMixin<RenderObject> {
  RenderSemantics(this._properties);

  SemanticsProperties _properties;
  SemanticsProperties get properties => _properties;
  set properties(SemanticsProperties value) {
    if (identical(_properties, value)) return;
    _properties = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  @override
  void performLayout() {
    final current = child;
    if (current == null) {
      size = constraints.constrain(Size.zero);
      return;
    }
    current.layout(constraints, parentUsesSize: true);
    final data = current.parentData as BoxParentData;
    data.offset = Offset.zero;
    size = constraints.constrain(current.size);
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    final current = child;
    if (current == null) return;
    final data = current.parentData as BoxParentData;
    current.paint(canvas, offset + data.offset);
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    final current = child;
    if (current == null) return false;
    final data = current.parentData as BoxParentData;
    return current.hitTest(result, position: position - data.offset);
  }
}

/// Output behavior for interactive terminals, pipelines, and automation.
enum OutputMode { interactive, plainText, json }

class OutputConfiguration extends InheritedWidget {
  const OutputConfiguration({
    super.key,
    required this.mode,
    this.color = true,
    this.alternateScreen = true,
    required super.child,
  });

  final OutputMode mode;
  final bool color;
  final bool alternateScreen;

  bool get interactive => mode == OutputMode.interactive;

  static OutputConfiguration of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<OutputConfiguration>() ??
        const OutputConfiguration(
          mode: OutputMode.interactive,
          child: _EmptyOutputWidget(),
        );
  }

  static OutputConfiguration? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<OutputConfiguration>();
  }

  @override
  bool updateShouldNotify(OutputConfiguration oldWidget) {
    return mode != oldWidget.mode ||
        color != oldWidget.color ||
        alternateScreen != oldWidget.alternateScreen;
  }
}

class _EmptyOutputWidget extends Widget {
  const _EmptyOutputWidget();

  @override
  Element createElement() => _EmptyOutputElement(this);
}

class _EmptyOutputElement extends Element {
  _EmptyOutputElement(super.widget);

  @override
  void performRebuild() {}

  @override
  void visitChildren(ElementVisitor visitor) {}
}

/// Serializable node in a captured semantics tree.
class SemanticsNodeData {
  SemanticsNodeData({
    required this.properties,
    List<SemanticsNodeData> children = const <SemanticsNodeData>[],
  }) : children = List<SemanticsNodeData>.unmodifiable(children);

  final SemanticsProperties properties;
  final List<SemanticsNodeData> children;

  Map<String, Object?> toJson() => <String, Object?>{
        ...properties.toJson(),
        if (children.isNotEmpty)
          'children': children.map((child) => child.toJson()).toList(),
      };

  String toPlainText({int depth = 0}) {
    final lines = <String>[];
    final prefix = '  ' * depth;
    final parts = <String>[
      if (properties.label case final label?) label,
      if (properties.value case final value?) value,
      if (properties.checked case final checked?)
        checked ? 'checked' : 'unchecked',
      if (properties.selected == true) 'selected',
      if (properties.enabled == false) 'disabled',
    ];
    if (!properties.hidden && parts.isNotEmpty) {
      lines.add('$prefix${parts.join(': ')}');
    }
    for (final child in children) {
      final text = child.toPlainText(depth: depth + (parts.isEmpty ? 0 : 1));
      if (text.isNotEmpty) lines.add(text);
    }
    return lines.join('\n');
  }
}

/// Captures semantic annotations from the mounted element tree.
class SemanticsSnapshot {
  SemanticsSnapshot(List<SemanticsNodeData> roots)
      : roots = List<SemanticsNodeData>.unmodifiable(roots);

  final List<SemanticsNodeData> roots;

  factory SemanticsSnapshot.capture([Element? root]) {
    final effectiveRoot = root ?? CinderBinding.instance.rootElement;
    if (effectiveRoot == null) return SemanticsSnapshot(const []);
    return SemanticsSnapshot(_captureElement(effectiveRoot));
  }

  String toPlainText() => roots
      .map((node) => node.toPlainText())
      .where((line) => line.isNotEmpty)
      .join('\n');

  Map<String, Object?> toJson() => <String, Object?>{
        'semantics': roots.map((node) => node.toJson()).toList(),
      };

  String toJsonString({bool pretty = false}) {
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : jsonEncode;
    return encoder is JsonEncoder
        ? encoder.convert(toJson())
        : jsonEncode(toJson());
  }

  static List<SemanticsNodeData> _captureElement(Element element) {
    final descendants = <SemanticsNodeData>[];
    element.visitChildren((child) {
      descendants.addAll(_captureElement(child));
    });
    final widget = element.widget;
    if (widget is! Semantics || widget.properties.hidden) return descendants;
    descendants.sort(
      (a, b) =>
          (a.properties.sortKey ?? 0).compareTo(b.properties.sortKey ?? 0),
    );
    return <SemanticsNodeData>[
      SemanticsNodeData(properties: widget.properties, children: descendants),
    ];
  }
}
