import 'package:meta/meta.dart';

import '../binding/scheduler_binding.dart';
import '../framework/framework.dart';
import '../framework/listenable.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import 'focusable.dart';

/// Determines how [FocusNode.unfocus] updates the enclosing focus scope.
enum UnfocusDisposition {
  /// Clear the focused child remembered by the current scope.
  scope,

  /// Restore the previously focused child when one is available.
  previouslyFocusedChild,
}

/// Owns the focus tree and the application's current primary focus.
///
/// Cinder exposes one process-wide manager, matching Flutter's
/// `FocusManager.instance` API. Nodes are attached by [Focus] and [FocusScope].
class FocusManager {
  FocusManager._() {
    rootScope = FocusScopeNode(
      debugLabel: 'Root Focus Scope',
      canRequestFocus: false,
      skipTraversal: true,
    );
    rootScope.attach(this, null);
  }

  static final FocusManager instance = FocusManager._();

  late final FocusScopeNode rootScope;

  final List<FocusNode> _nodes = <FocusNode>[];
  FocusNode? _primaryFocus;

  /// The node currently receiving keyboard events.
  FocusNode? get primaryFocus => _primaryFocus;

  @internal
  void register(FocusNode node) {
    if (!_nodes.contains(node)) {
      _nodes.add(node);
    }
  }

  @internal
  void unregister(FocusNode node) {
    if (identical(_primaryFocus, node) ||
        (_primaryFocus?.ancestors.contains(node) ?? false)) {
      _setPrimaryFocus(null);
    }
    _nodes.remove(node);
  }

  bool _ancestorsAllowFocus(FocusNode node) {
    for (final ancestor in node.ancestors) {
      if (ancestor is FocusScopeNode && !ancestor.descendantsAreFocusable) {
        return false;
      }
    }
    return true;
  }

  bool _ancestorsAllowTraversal(FocusNode node) {
    for (final ancestor in node.ancestors) {
      if (ancestor is FocusScopeNode && !ancestor.descendantsAreTraversable) {
        return false;
      }
    }
    return true;
  }

  bool _canRequestFocus(FocusNode node) {
    return node.attached && node.canRequestFocus && _ancestorsAllowFocus(node);
  }

  List<FocusNode> _traversableNodes({FocusScopeNode? scope}) {
    return _nodes
        .where((node) {
          if (node is FocusScopeNode) return false;
          if (!_canRequestFocus(node) || node.skipTraversal) return false;
          if (!_ancestorsAllowTraversal(node)) return false;
          if (scope != null && !node.ancestors.contains(scope)) return false;
          return true;
        })
        .toList(growable: false);
  }

  @internal
  bool requestFocus(FocusNode node) {
    if (!_canRequestFocus(node)) return false;
    _setPrimaryFocus(node);
    return true;
  }

  void _setPrimaryFocus(FocusNode? node) {
    if (identical(_primaryFocus, node)) return;

    final oldFocus = _primaryFocus;
    final affected = <FocusNode>{
      if (oldFocus != null) oldFocus,
      if (oldFocus != null) ...oldFocus.ancestors,
      if (node != null) node,
      if (node != null) ...node.ancestors,
    };

    _primaryFocus = node;
    node?.nearestScope?._rememberFocusedChild(node);

    for (final affectedNode in affected) {
      affectedNode.notifyFocusListeners();
    }
  }

  @internal
  void clearFocus(FocusNode node) {
    if (identical(_primaryFocus, node) ||
        (_primaryFocus?.ancestors.contains(node) ?? false)) {
      _setPrimaryFocus(null);
    }
  }

  /// Moves focus to the next traversable node, wrapping at the end.
  bool nextFocus([FocusNode? from]) {
    return _moveFocus(from ?? _primaryFocus, forward: true);
  }

  /// Moves focus to the previous traversable node, wrapping at the beginning.
  bool previousFocus([FocusNode? from]) {
    return _moveFocus(from ?? _primaryFocus, forward: false);
  }

  bool _moveFocus(FocusNode? from, {required bool forward}) {
    final scope = from?.nearestScope;
    var candidates = _traversableNodes(scope: scope);
    if (candidates.isEmpty && scope != null) {
      candidates = _traversableNodes(scope: scope.parentScope);
    }
    if (candidates.isEmpty) {
      candidates = _traversableNodes();
    }
    if (candidates.isEmpty) return false;

    final currentIndex = from == null ? -1 : candidates.indexOf(from);
    final nextIndex = forward
        ? (currentIndex + 1) % candidates.length
        : (currentIndex <= 0 ? candidates.length - 1 : currentIndex - 1);
    return requestFocus(candidates[nextIndex]);
  }

  @internal
  FocusNode? firstTraversableDescendant(FocusScopeNode scope) {
    final remembered = scope.focusedChild;
    if (remembered != null && _canRequestFocus(remembered)) {
      return remembered;
    }
    final candidates = _traversableNodes(scope: scope);
    return candidates.isEmpty ? null : candidates.first;
  }
}

/// A persistent object that participates in Cinder's focus tree.
class FocusNode implements Listenable {
  FocusNode({
    this.debugLabel,
    this.onKeyEvent,
    bool canRequestFocus = true,
    bool skipTraversal = false,
  }) : _canRequestFocus = canRequestFocus,
       _skipTraversal = skipTraversal;

  final String? debugLabel;
  KeyEventHandler? onKeyEvent;

  final List<VoidCallback> _listeners = <VoidCallback>[];
  FocusManager? _manager;
  FocusScopeNode? _parent;
  bool _disposed = false;
  bool _canRequestFocus;
  bool _skipTraversal;

  /// Whether this node is currently attached to a [Focus] widget.
  bool get attached => _manager != null;

  /// Whether this node may become primary focus.
  bool get canRequestFocus => _canRequestFocus;
  set canRequestFocus(bool value) {
    if (_canRequestFocus == value) return;
    _canRequestFocus = value;
    if (!value && hasPrimaryFocus) {
      unfocus();
    }
    notifyFocusListeners();
  }

  /// Whether traversal skips this node while still allowing explicit focus.
  bool get skipTraversal => _skipTraversal;
  set skipTraversal(bool value) {
    if (_skipTraversal == value) return;
    _skipTraversal = value;
    notifyFocusListeners();
  }

  /// The closest enclosing focus scope.
  FocusScopeNode? get nearestScope => _parent;

  /// Ancestors from the nearest scope to the root scope.
  Iterable<FocusNode> get ancestors sync* {
    FocusNode? current = _parent;
    while (current != null) {
      yield current;
      current = current._parent;
    }
  }

  /// Whether this node or one of its descendants has primary focus.
  bool get hasFocus {
    final primary = FocusManager.instance.primaryFocus;
    return identical(primary, this) ||
        (primary?.ancestors.contains(this) ?? false);
  }

  /// Whether this exact node receives keyboard events.
  bool get hasPrimaryFocus =>
      identical(FocusManager.instance.primaryFocus, this);

  /// Requests primary focus for this node.
  void requestFocus() {
    _manager?.requestFocus(this);
  }

  /// Removes focus from this node.
  void unfocus({UnfocusDisposition disposition = UnfocusDisposition.scope}) {
    final scope = nearestScope;
    if (disposition == UnfocusDisposition.previouslyFocusedChild &&
        scope?.focusedChild != null &&
        !identical(scope!.focusedChild, this)) {
      scope.focusedChild!.requestFocus();
      return;
    }
    _manager?.clearFocus(this);
    if (disposition == UnfocusDisposition.scope) {
      scope?._forgetFocusedChild(this);
    }
  }

  bool nextFocus() => _manager?.nextFocus(this) ?? false;
  bool previousFocus() => _manager?.previousFocus(this) ?? false;

  @internal
  void attach(FocusManager manager, FocusScopeNode? parent) {
    if (_disposed) {
      throw StateError('Cannot attach a disposed FocusNode.');
    }
    if (identical(_manager, manager) && identical(_parent, parent)) return;
    detach();
    _manager = manager;
    _parent = parent;
    parent?._addChild(this);
    manager.register(this);
    notifyFocusListeners();
  }

  @internal
  void detach() {
    final manager = _manager;
    if (manager == null) return;
    _parent?._removeChild(this);
    _parent = null;
    _manager = null;
    manager.unregister(this);
    notifyFocusListeners();
  }

  @internal
  void notifyFocusListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) {
      throw StateError('Cannot listen to a disposed FocusNode.');
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Releases resources owned by this node.
  void dispose() {
    if (_disposed) return;
    detach();
    _disposed = true;
    _listeners.clear();
  }

  @override
  String toString() {
    final label = debugLabel == null ? '' : '($debugLabel)';
    return '$runtimeType$label${hasPrimaryFocus ? ' [PRIMARY FOCUS]' : ''}';
  }
}

/// A focus node that groups descendants and remembers its focused child.
class FocusScopeNode extends FocusNode {
  FocusScopeNode({
    super.debugLabel,
    super.canRequestFocus,
    super.skipTraversal,
    this.descendantsAreFocusable = true,
    this.descendantsAreTraversable = true,
  });

  final List<FocusNode> _children = <FocusNode>[];
  FocusNode? _focusedChild;

  bool descendantsAreFocusable;
  bool descendantsAreTraversable;

  FocusNode? get focusedChild => _focusedChild;
  FocusScopeNode? get parentScope => nearestScope;
  Iterable<FocusNode> get children => List<FocusNode>.unmodifiable(_children);

  void _addChild(FocusNode node) {
    if (!_children.contains(node)) _children.add(node);
  }

  void _removeChild(FocusNode node) {
    _children.remove(node);
    _forgetFocusedChild(node);
  }

  void _rememberFocusedChild(FocusNode node) {
    _focusedChild = node;
    nearestScope?._rememberFocusedChild(this);
  }

  void _forgetFocusedChild(FocusNode node) {
    if (identical(_focusedChild, node)) {
      _focusedChild = null;
    }
  }

  /// Requests focus for [node], or the remembered/first traversable descendant.
  void requestScopeFocus([FocusNode? node]) {
    final target =
        node ??
        FocusManager.instance.firstTraversableDescendant(this) ??
        (canRequestFocus ? this : null);
    target?.requestFocus();
  }
}

/// Controls keyboard focus for a widget subtree.
class Focus extends StatefulWidget {
  const Focus({
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.skipTraversal = false,
    this.onFocusChange,
    this.onKeyEvent,
    required this.child,
  });

  final FocusNode? focusNode;
  final bool autofocus;
  final bool canRequestFocus;
  final bool skipTraversal;
  final void Function(bool hasFocus)? onFocusChange;
  final KeyEventHandler? onKeyEvent;
  final Widget child;

  /// Returns the nearest focus node and establishes a dependency.
  static FocusNode of(BuildContext context) {
    final node = maybeOf(context);
    if (node == null) {
      throw StateError('No Focus ancestor found in this BuildContext.');
    }
    return node;
  }

  /// Returns the nearest focus node, or null when no [Focus] exists.
  static FocusNode? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_FocusMarker>()?.node;
  }

  @override
  State<Focus> createState() => _FocusState();
}

class _FocusState extends State<Focus> {
  late FocusNode _node;
  bool _ownsNode = false;
  FocusScopeNode? _scope;
  bool _autofocusScheduled = false;
  bool _lastHasFocus = false;

  @override
  void initState() {
    super.initState();
    _initNode();
  }

  void _initNode() {
    _ownsNode = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode();
    _node
      ..canRequestFocus = widget.canRequestFocus
      ..skipTraversal = widget.skipTraversal
      ..addListener(_handleFocusChange);
    _lastHasFocus = _node.hasFocus;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope =
        FocusScope.maybeOf(context) ?? FocusManager.instance.rootScope;
    if (!identical(nextScope, _scope) || !_node.attached) {
      _scope = nextScope;
      _node.attach(FocusManager.instance, nextScope);
    }
    _scheduleAutofocus();
  }

  @override
  void didUpdateWidget(Focus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      _node.removeListener(_handleFocusChange);
      _node.detach();
      if (_ownsNode) _node.dispose();
      _initNode();
      _node.attach(
        FocusManager.instance,
        _scope ?? FocusManager.instance.rootScope,
      );
    }
    _node
      ..canRequestFocus = widget.canRequestFocus
      ..skipTraversal = widget.skipTraversal;
    if (widget.autofocus && !oldWidget.autofocus) {
      _autofocusScheduled = false;
      _scheduleAutofocus();
    }
  }

  void _scheduleAutofocus() {
    if (!widget.autofocus || _autofocusScheduled) return;
    _autofocusScheduled = true;

    // The node is already attached when didChangeDependencies reaches here.
    // Requesting focus synchronously makes the first key event deterministic
    // and avoids requiring an extra frame after pumpWidget/runApp.
    if (_node.attached && !_node.hasFocus) {
      _node.requestFocus();
    }
  }

  void _handleFocusChange() {
    final hasFocus = _node.hasFocus;
    if (hasFocus != _lastHasFocus) {
      _lastHasFocus = hasFocus;
      widget.onFocusChange?.call(hasFocus);
    }
    if (mounted) setState(() {});
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.tab) {
      return event.isShiftPressed ? _node.previousFocus() : _node.nextFocus();
    }
    return widget.onKeyEvent?.call(event) ??
        _node.onKeyEvent?.call(event) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return _FocusMarker(
      node: _node,
      hasPrimaryFocus: _node.hasPrimaryFocus,
      child: Focusable(
        focused: _node.hasPrimaryFocus,
        onKeyEvent: _handleKeyEvent,
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    _node.detach();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }
}

class _FocusMarker extends InheritedWidget {
  const _FocusMarker({
    required this.node,
    required this.hasPrimaryFocus,
    required super.child,
  });

  final FocusNode node;
  final bool hasPrimaryFocus;

  @override
  bool updateShouldNotify(_FocusMarker oldWidget) {
    return !identical(node, oldWidget.node) ||
        hasPrimaryFocus != oldWidget.hasPrimaryFocus;
  }
}

/// Establishes a focus traversal scope for descendants.
class FocusScope extends StatefulWidget {
  const FocusScope({
    super.key,
    this.node,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.descendantsAreFocusable = true,
    this.descendantsAreTraversable = true,
    required this.child,
  });

  final FocusScopeNode? node;
  final bool autofocus;
  final bool canRequestFocus;
  final bool descendantsAreFocusable;
  final bool descendantsAreTraversable;
  final Widget child;

  static FocusScopeNode of(BuildContext context) {
    return maybeOf(context) ?? FocusManager.instance.rootScope;
  }

  static FocusScopeNode? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_FocusScopeMarker>()
        ?.node;
  }

  @override
  State<FocusScope> createState() => _FocusScopeState();
}

class _FocusScopeState extends State<FocusScope> {
  late FocusScopeNode _node;
  bool _ownsNode = false;
  FocusScopeNode? _parentScope;
  bool _autofocusScheduled = false;

  @override
  void initState() {
    super.initState();
    _initNode();
  }

  void _initNode() {
    _ownsNode = widget.node == null;
    _node = widget.node ?? FocusScopeNode();
    _updateNodeProperties();
  }

  void _updateNodeProperties() {
    _node
      ..canRequestFocus = widget.canRequestFocus
      ..descendantsAreFocusable = widget.descendantsAreFocusable
      ..descendantsAreTraversable = widget.descendantsAreTraversable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextParent =
        FocusScope.maybeOf(context) ?? FocusManager.instance.rootScope;
    if (!identical(nextParent, _node) &&
        (!identical(nextParent, _parentScope) || !_node.attached)) {
      _parentScope = nextParent;
      _node.attach(FocusManager.instance, nextParent);
    }
    _scheduleAutofocus();
  }

  @override
  void didUpdateWidget(FocusScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.node, oldWidget.node)) {
      _node.detach();
      if (_ownsNode) _node.dispose();
      _initNode();
      _node.attach(
        FocusManager.instance,
        _parentScope ?? FocusManager.instance.rootScope,
      );
    } else {
      _updateNodeProperties();
    }
    if (widget.autofocus && !oldWidget.autofocus) {
      _autofocusScheduled = false;
      _scheduleAutofocus();
    }
  }

  void _scheduleAutofocus() {
    if (!widget.autofocus || _autofocusScheduled) return;
    _autofocusScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestScopeFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _FocusScopeMarker(node: _node, child: widget.child);
  }

  @override
  void dispose() {
    _node.detach();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }
}

class _FocusScopeMarker extends InheritedWidget {
  const _FocusScopeMarker({required this.node, required super.child});

  final FocusScopeNode node;

  @override
  bool updateShouldNotify(_FocusScopeMarker oldWidget) {
    return !identical(node, oldWidget.node);
  }
}
