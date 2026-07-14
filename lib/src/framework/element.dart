part of 'framework.dart';

typedef ConditionalElementVisitor = bool Function(Element element);

enum _ElementLifecycle {
  initial,
  active,
  inactive,
  defunct,
}

/// Represents a node in the widget tree
abstract class Element implements BuildContext {
  Element(this._component);

  Widget? _component;
  @override
  Widget get widget => _component!;

  Element? _parent;
  @override
  Element? get parent => _parent;

  _ElementLifecycle _lifecycleState = _ElementLifecycle.initial;

  /// Whether this element is currently mounted in the element tree.
  bool get mounted => _lifecycleState != _ElementLifecycle.defunct;

  dynamic _slot;
  dynamic get slot => _slot;

  int _depth = 0;
  int get depth => _depth;

  bool _dirty = true;
  bool get dirty => _dirty;

  bool _inDirtyList = false;

  BuildOwner? _owner;
  @override
  BuildOwner? get owner => _owner;

  @override
  CinderBinding get binding => CinderBinding.instance;

  @mustCallSuper
  void mount(Element? parent, dynamic newSlot) {
    assert(_lifecycleState == _ElementLifecycle.initial);
    assert(
        parent == null || parent._lifecycleState == _ElementLifecycle.active);
    _parent = parent;
    _slot = newSlot;
    _depth = parent != null ? parent.depth + 1 : 1;
    _lifecycleState = _ElementLifecycle.active;
    if (parent != null) {
      _owner = parent.owner;
    }
    final Key? key = widget.key;
    if (key is GlobalKey) {
      owner!._registerGlobalKey(key, this);
    }
    _updateInheritance();
  }

  void update(Widget newWidget) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(newWidget != widget);
    assert(Widget.canUpdate(widget, newWidget));
    _component = newWidget;
  }

  void updateSlot(dynamic newSlot) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(parent != null);
    assert(parent!._lifecycleState == _ElementLifecycle.active);
    _slot = newSlot;
  }

  void detachRenderObject() {
    visitChildren((Element child) {
      child.detachRenderObject();
    });
  }

  void attachRenderObject(dynamic newSlot) {}

  /// Returns the RenderObject associated with this Element or its descendants.
  ///
  /// If this Element is a RenderObjectElement, returns its renderObject.
  /// Otherwise, walks down the tree to find the first RenderObjectElement descendant.
  RenderObject? get renderObject {
    Element? current = this;
    // ignore: unnecessary_null_comparison
    while (current != null) {
      if (current._lifecycleState == _ElementLifecycle.defunct) {
        break;
      } else if (current is RenderObjectElement) {
        return current.renderObject;
      } else {
        // For non-RenderObjectElements, we need to check their children
        // This is simplified - Flutter has a more complex renderObjectAttachingChild
        // For now, just return null for non-RenderObjectElements
        break;
      }
    }
    return null;
  }

  void unmount() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    final Key? key = widget.key;
    if (key is GlobalKey) {
      owner!._unregisterGlobalKey(key, this);
    }
    // Release resources to reduce the severity of memory leaks caused by
    // defunct, but accidentally retained Elements.
    _component = null;
    _dependencies = null;
    _lifecycleState = _ElementLifecycle.defunct;
  }

  /// Propagates a slot change down the element tree until it reaches a
  /// [RenderObjectElement], which will call [moveRenderObjectChild] on its
  /// ancestor to reorder the render object in the parent's child list.
  void updateSlotForChild(Element child, dynamic newSlot) {
    void visit(Element element) {
      element.updateSlot(newSlot);
      if (element is! RenderObjectElement) {
        element.visitChildren(visit);
      }
    }

    visit(child);
  }

  @protected
  Element? updateChild(Element? child, Widget? newWidget, dynamic newSlot) {
    if (newWidget == null) {
      if (child != null) {
        deactivateChild(child);
      }
      return null;
    }

    final Element newChild;
    if (child != null) {
      if (child.widget == newWidget) {
        if (child.slot != newSlot) {
          updateSlotForChild(child, newSlot);
        }
        newChild = child;
      } else if (Widget.canUpdate(child.widget, newWidget)) {
        child.update(newWidget);
        newChild = child;
      } else {
        deactivateChild(child);
        newChild = inflateWidget(newWidget, newSlot);
      }
    } else {
      newChild = inflateWidget(newWidget, newSlot);
    }

    return newChild;
  }

  @protected
  Element inflateWidget(Widget newWidget, dynamic newSlot) {
    final Element newChild = newWidget.createElement();
    newChild.mount(this, newSlot);
    return newChild;
  }

  @protected
  void deactivateChild(Element child) {
    assert(child._parent == this);
    child._parent = null;
    child.detachRenderObject();
    owner!._inactiveElements.add(child);
  }

  @mustCallSuper
  void activate() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    assert(parent != null);
    assert(parent!._lifecycleState == _ElementLifecycle.active);
    assert(depth > 0);
    _lifecycleState = _ElementLifecycle.active;
    visitChildren((Element child) {
      child.activate();
    });
    _updateInheritance();
  }

  void _updateInheritance() {
    assert(_lifecycleState == _ElementLifecycle.active);
    _inheritedElements = _parent?._inheritedElements;
  }

  void deactivate() {
    assert(_lifecycleState == _ElementLifecycle.active);
    _ensureDeactivated();
  }

  void _ensureDeactivated() {
    if (_dependencies case final Set<InheritedElement> dependencies?
        when dependencies.isNotEmpty) {
      for (final dependency in dependencies) {
        dependency.removeDependent(this);
      }
    }
    _inheritedElements = null;
    _lifecycleState = _ElementLifecycle.inactive;
  }

  void markNeedsBuild() {
    assert(_lifecycleState == _ElementLifecycle.active);
    if (_dirty) {
      return;
    }
    _dirty = true;
    owner!.scheduleBuildFor(this);
  }

  void rebuild() {
    assert(_lifecycleState == _ElementLifecycle.active);
    performRebuild();
  }

  @protected
  void performRebuild();

  void visitChildren(ElementVisitor visitor);

  @override
  void visitChildElements(ElementVisitor visitor) {
    visitChildren(visitor);
  }

  @override
  void visitAncestorElements(ConditionalElementVisitor visitor) {
    Element? ancestor = _parent;
    while (ancestor != null && visitor(ancestor)) {
      ancestor = ancestor._parent;
    }
  }

  @protected
  List<Element> updateChildren(
      List<Element> oldChildren, List<Widget> newWidgets) {
    Element? replaceWithNullIfForgotten(Element child) {
      return _owner!._forgottenChildren.contains(child) ? null : child;
    }

    // Helper function to create appropriate slot for multi-child elements
    Object? slotFor(int newChildIndex, Element? previousChild) {
      // For MultiChildRenderObjectElement, create an IndexedSlot
      if (this is MultiChildRenderObjectElement) {
        return IndexedSlot(newChildIndex, previousChild);
      }
      // For other elements, just return the previous child (legacy behavior)
      return previousChild;
    }

    int newChildrenTop = 0;
    int oldChildrenTop = 0;
    int newChildrenBottom = newWidgets.length - 1;
    int oldChildrenBottom = oldChildren.length - 1;

    final List<Element?> newChildren =
        List<Element?>.filled(newWidgets.length, null);

    Element? previousChild;

    // Update the top of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      final Element? oldChild =
          replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
      final Widget newWidget = newWidgets[newChildrenTop];
      assert(oldChild == null ||
          oldChild._lifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      final Element newChild = updateChild(
          oldChild, newWidget, slotFor(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Scan the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      final Element? oldChild =
          replaceWithNullIfForgotten(oldChildren[oldChildrenBottom]);
      final Widget newWidget = newWidgets[newChildrenBottom];
      assert(oldChild == null ||
          oldChild._lifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      oldChildrenBottom -= 1;
      newChildrenBottom -= 1;
    }

    // Scan the old children in the middle of the list.
    final bool haveOldChildren = oldChildrenTop <= oldChildrenBottom;
    Map<Key, Element>? oldKeyedChildren;
    if (haveOldChildren) {
      oldKeyedChildren = <Key, Element>{};
      while (oldChildrenTop <= oldChildrenBottom) {
        final Element? oldChild =
            replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
        assert(oldChild == null ||
            oldChild._lifecycleState == _ElementLifecycle.active);
        if (oldChild != null) {
          if (oldChild.widget.key != null) {
            oldKeyedChildren[oldChild.widget.key!] = oldChild;
          } else {
            deactivateChild(oldChild);
          }
        }
        oldChildrenTop += 1;
      }
    }

    // Update the middle of the list.
    while (newChildrenTop <= newChildrenBottom) {
      Element? oldChild;
      final Widget newWidget = newWidgets[newChildrenTop];
      if (newWidget.key != null) {
        final Key key = newWidget.key!;
        if (oldKeyedChildren != null) {
          oldChild = oldKeyedChildren[key];
          if (oldChild != null) {
            if (Widget.canUpdate(oldChild.widget, newWidget)) {
              oldKeyedChildren.remove(key);
            } else {
              oldChild = null;
            }
          }
        }
      }
      assert(oldChild == null || Widget.canUpdate(oldChild.widget, newWidget));
      final Element newChild = updateChild(
          oldChild, newWidget, slotFor(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
    }

    // We've scanned the whole list.
    assert(oldChildrenTop == oldChildrenBottom + 1);
    assert(newChildrenTop == newChildrenBottom + 1);
    assert(newWidgets.length - newChildrenTop ==
        oldChildren.length - oldChildrenTop);
    newChildrenBottom = newWidgets.length - 1;
    oldChildrenBottom = oldChildren.length - 1;

    // Update the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      final Element oldChild = oldChildren[oldChildrenTop];
      assert(replaceWithNullIfForgotten(oldChild) != null);
      assert(oldChild._lifecycleState == _ElementLifecycle.active);
      final Widget newWidget = newWidgets[newChildrenTop];
      assert(Widget.canUpdate(oldChild.widget, newWidget));
      final Element newChild = updateChild(
          oldChild, newWidget, slotFor(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Clean up any of the remaining middle nodes from the old list.
    if (oldKeyedChildren != null && oldKeyedChildren.isNotEmpty) {
      for (final Element oldChild in oldKeyedChildren.values) {
        if (replaceWithNullIfForgotten(oldChild) != null) {
          deactivateChild(oldChild);
        }
      }
    }

    assert(newChildren.every((Element? element) => element != null));
    return newChildren.cast<Element>();
  }

  void forgetChild(Element child) {
    assert(child._parent == this);
    _owner?._forgottenChildren.add(child);
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>(
      {Object? aspect}) {
    if (_inheritedElements?[T] case final InheritedElement ancestor) {
      if (dependOnInheritedElement(ancestor, aspect: aspect)
          case final T widget) {
        return widget;
      }

      throw Exception(
          'dependOnInheritedWidgetOfExactType: $T is not an $InheritedWidget');
    }
    return null;
  }

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor,
      {Object? aspect}) {
    (_dependencies ??= HashSet<InheritedElement>()).add(ancestor);
    ancestor.updateDependencies(this, aspect);
    return ancestor.widget;
  }

  @override
  InheritedElement?
      getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() {
    return _inheritedElements?[T];
  }

  PersistentHashMap<Type, InheritedElement>? _inheritedElements;
  Set<InheritedElement>? _dependencies;

  void didChangeDependencies() {
    markNeedsBuild();
  }

  @override
  bool get debugDoingBuild => false;

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    Element? ancestor = parent;
    while (ancestor != null) {
      if (ancestor.widget case final T widget) {
        return widget;
      }
      ancestor = ancestor.parent;
    }

    return null;
  }

  @override
  T? findAncestorStateOfType<T extends State>() {
    Element? ancestor = parent;
    while (ancestor != null) {
      if (ancestor case StatefulElement(:final T state)) {
        return state;
      }
      ancestor = ancestor.parent;
    }
    return null;
  }

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() {
    Element? ancestor = parent;
    while (ancestor != null) {
      if (ancestor case RenderObjectElement(:final T renderObject)) {
        return renderObject;
      }
      ancestor = ancestor.parent;
    }

    return null;
  }

  @override
  BoxConstraints get constraints {
    final renderObject = findAncestorRenderObjectOfType<RenderObject>();
    return renderObject?.constraints ?? const BoxConstraints();
  }

  /// Called whenever the application is reassembled during debugging, for
  /// example during hot reload.
  ///
  /// This method should rerun any initialization logic that depends on global
  /// state. The method will mark this element as needing to be rebuilt and
  /// then recursively call reassemble on all child elements.
  @protected
  @mustCallSuper
  void reassemble() {
    markNeedsBuild();
    visitChildren((Element child) {
      child.reassemble();
    });
  }
}
