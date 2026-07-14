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
  T? findAncestorComponentOfExactType<T extends Widget>();

  /// Returns the state of the nearest ancestor [StatefulWidget].
  T? findAncestorStateOfType<T extends State>();

  /// Visit all the ancestor elements.
  void visitAncestorElements(ConditionalElementVisitor visitor);

  /// Returns the render object of the nearest ancestor [RenderObjectWidget].
  T? findAncestorRenderObjectOfType<T extends RenderObject>();

  /// Obtains the nearest [InheritedComponent] of the given type T and
  /// registers this context to be rebuilt when that widget changes.
  T? dependOnInheritedComponentOfExactType<T extends InheritedComponent>(
      {Object? aspect});

  /// Registers this context with an [InheritedElement].
  InheritedComponent dependOnInheritedElement(InheritedElement ancestor,
      {Object? aspect});

  InheritedElement? getElementForInheritedComponentOfExactType<
      T extends InheritedComponent>();

  /// Visit all the children elements.
  void visitChildElements(ElementVisitor visitor);

  /// Returns the size constraints from the nearest [RenderObject] ancestor.
  BoxConstraints get constraints {
    final renderObject = findAncestorRenderObjectOfType<RenderObject>();
    return renderObject?.constraints ?? const BoxConstraints();
  }
}
