part of 'framework.dart';

/// An element that has a build method.
abstract class BuildableElement extends Element {
  BuildableElement(super.widget);

  Element? _child;

  bool _debugDoingBuild = false;
  @override
  bool get debugDoingBuild => _debugDoingBuild;

  void _firstBuild() {
    rebuild();
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    assert(_child == null);
    _firstBuild();
  }

  @override
  void performRebuild() {
    _willBuildDependencies();
    assert(() {
      _debugDoingBuild = true;
      return true;
    }());

    Widget? built;
    try {
      built = build();
    } catch (e, stack) {
      // Handle build errors
      _debugDoingBuild = false;
      built = _reportBuildError(e, stack);
    } finally {
      _dirty = false;
      assert(() {
        _debugDoingBuild = false;
        return true;
      }());
      _didBuildDependencies();
    }

    try {
      _child = updateChild(_child, built, slot);
    } catch (e, stack) {
      // Mounting or updating the child failed (initState, didUpdateWidget,
      // createRenderObject, ...), possibly halfway through its subtree.
      // Abandon that subtree rather than updating it again, as Flutter does,
      // but take its render objects out of the render tree.
      final ErrorWidget errorWidget = _reportBuildError(e, stack);
      final Element? failedChild = _child;
      if (failedChild != null && failedChild._parent == this) {
        failedChild.detachRenderObject();
      }
      _child = updateChild(null, errorWidget, slot);
    }
  }

  ErrorWidget _reportBuildError(Object error, StackTrace stack) {
    CinderError.reportError(
      CinderErrorDetails(
        exception: error,
        stack: stack,
        library: 'cinder framework',
        context: 'while building $runtimeType',
      ),
    );
    return ErrorWidget(error: error, stackTrace: stack);
  }

  @protected
  Widget build();

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(_child == child);
    _child = null;
  }
}

/// Widget shown when there's an error during build.
///
/// Uses [RenderTUIErrorBox] to display a red bordered box with the error
/// message and stack trace, matching the visual style of layout/paint errors.
class ErrorWidget extends SingleChildRenderObjectWidget {
  const ErrorWidget({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTUIErrorBox(
      message: 'Build error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTUIErrorBox renderObject,
  ) {
    // RenderTUIErrorBox is immutable after creation
  }
}
