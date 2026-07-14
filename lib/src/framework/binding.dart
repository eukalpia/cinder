part of 'framework.dart';

/// The glue between the widget layer and the terminal rendering layer
abstract class CinderBinding {
  static CinderBinding? _instance;
  static CinderBinding get instance => _instance!;

  CinderBinding() {
    assert(_instance == null, 'Only one TuiBinding instance allowed');
    _instance = this;
    initializeBinding();
  }

  /// Initialize the binding.
  ///
  /// Subclasses and mixins should override this to perform their
  /// initialization in the constructor. Implementations must call
  /// super.initializeBinding().
  @protected
  @mustCallSuper
  void initializeBinding() {
    initServiceExtensions();
  }

  /// Called when the binding is initialized to register service extensions.
  /// Subclasses should override this and call super.
  @protected
  @mustCallSuper
  void initServiceExtensions() {
    // Base class has no extensions to register
  }

  /// Registers a service extension method with the given name.
  /// The full name will be "ext.cinder.name".
  @protected
  void registerServiceExtension({
    required String name,
    required Future<Map<String, dynamic>> Function(
            Map<String, String> parameters)
        callback,
  }) {
    developer.registerExtension(
      'ext.cinder.$name',
      (String method, Map<String, String> parameters) async {
        final result = await callback(parameters);
        return developer.ServiceExtensionResponse.result(
          json.encode(result),
        );
      },
    );
  }

  /// Registers a service extension for a boolean value.
  @protected
  void registerBoolServiceExtension({
    required String name,
    required Future<bool> Function() getter,
    required Future<void> Function(bool value) setter,
  }) {
    registerServiceExtension(
      name: name,
      callback: (Map<String, String> parameters) async {
        if (parameters.containsKey('enabled')) {
          await setter(parameters['enabled'] == 'true');
        }
        return <String, dynamic>{'enabled': (await getter()).toString()};
      },
    );
  }

  /// Clear the singleton instance - only for testing
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  BuildOwner? _buildOwner;
  BuildOwner get buildOwner => _buildOwner ??= createBuildOwner();

  Element? _rootElement;
  Element? get rootElement => _rootElement;

  @protected
  BuildOwner createBuildOwner() {
    return BuildOwner(onNeedsBuild);
  }

  void attachRootWidget(Widget rootWidget) {
    if (_rootElement != null) {
      _rootElement!.deactivate();
      _rootElement!.unmount();
    }
    _rootElement = rootWidget.createElement();
    // Set the owner before mounting (root has no parent to inherit from)
    _rootElement!._owner = buildOwner;
    _rootElement!.mount(null, null);
  }

  void scheduleFrame() {
    // Schedule frame to be drawn asynchronously
    // This allows batching of updates
    scheduleMicrotask(() => drawFrame());
  }

  void onNeedsBuild() {
    scheduleFrame();
  }

  void drawFrame() {
    buildOwner.buildScope(rootElement!, () {
      // Layout phase would go here
      // Paint phase would go here
    });
    buildOwner.finalizeTree();
  }

  /// Cause the entire subtree rooted at the root element to be entirely
  /// rebuilt. This is used by development tools when the application code has
  /// changed and is being hot-reloaded, to cause the widget tree to pick up any
  /// changed implementations.
  ///
  /// This is expensive and should not be called except during development.
  void reassemble() {
    if (rootElement != null) {
      rootElement!.reassemble();
    }
  }

  /// Called to actually cause the application to reassemble, e.g. after a hot reload.
  ///
  /// This method is called by the hot reload mechanism to trigger a full rebuild
  /// of the widget tree with the new code.
  @protected
  @mustCallSuper
  Future<void> performReassemble() async {
    reassemble();
    scheduleFrame();
    return Future<void>.value();
  }
}

/// InheritedWidget provides a way to pass data down the widget tree.
abstract class InheritedWidget extends ProxyWidget {
  const InheritedWidget({super.key, required super.child});

  @override
  InheritedElement createElement() => InheritedElement(this);

  /// Whether the framework should notify components that inherit from this widget.
  @protected
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}

/// Element for [InheritedWidget].
class InheritedElement extends ProxyElement {
  InheritedElement(InheritedWidget super.widget);

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  final Map<Element, Object?> _dependents = HashMap<Element, Object?>();

  @override
  void updated(covariant InheritedWidget oldWidget) {
    if (widget.updateShouldNotify(oldWidget)) {
      super.updated(oldWidget);
    }
  }

  @override
  void _updateInheritance() {
    _inheritedElements =
        (_parent?._inheritedElements ?? const PersistentHashMap.empty())
            .put(widget.runtimeType, this);
  }

  @protected
  Object? getDependencies(Element dependent) {
    return _dependents[dependent];
  }

  @protected
  void setDependencies(Element dependent, Object? value) {
    _dependents[dependent] = value;
  }

  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(dependent, null);
  }

  @override
  void notifyClients(covariant InheritedWidget oldWidget) {
    for (final Element dependent in _dependents.keys) {
      notifyDependent(oldWidget, dependent);
    }
  }

  @protected
  void notifyDependent(
      covariant InheritedWidget oldWidget, covariant Element dependent) {
    dependent.didChangeDependencies();
  }

  @protected
  @mustCallSuper
  void removeDependent(Element dependent) {
    _dependents.remove(dependent);
  }
}
