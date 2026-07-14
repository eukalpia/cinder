part of 'framework.dart';

/// Interface for locating components and accessing state
abstract class BuildContext {
  /// The current widget associated with this [BuildContext].
  Widget get widget;

  /// The [BuildOwner] for this context.
  BuildOwner? get owner;

  /// Whether the widget is currently being built.
  bool get debugDoingBuild;

  /// The parent element.
  Element? get parent;

  /// The current binding.
  CinderBinding get binding;

  /// Returns the nearest ancestor widget of the given type T.
  T? findAncestorWidgetOfExactType<T extends Widget>();

  /// Returns the state of the nearest ancestor [StatefulWidget].
  T? findAncestorStateOfType<T extends State>();

  /// Visit all the ancestor elements.
  void visitAncestorElements(ConditionalElementVisitor visitor);

  /// Returns the render object of the nearest ancestor [RenderObjectWidget].
  T? findAncestorRenderObjectOfType<T extends RenderObject>();

  /// Obtains the nearest [InheritedWidget] of the given type T and
  /// registers this context to be rebuilt when that widget changes.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>(
      {Object? aspect});

  /// Registers this context with an [InheritedElement].
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor,
      {Object? aspect});

  InheritedElement?
      getElementForInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// Visit all the children elements.
  void visitChildElements(ElementVisitor visitor);

  /// Returns the size constraints from the nearest [RenderObject] ancestor.
  BoxConstraints get constraints {
    final renderObject = findAncestorRenderObjectOfType<RenderObject>();
    return renderObject?.constraints ?? const BoxConstraints();
  }
}
