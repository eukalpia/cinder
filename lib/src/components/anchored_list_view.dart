import 'dart:math' as math;

import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';

import '../rendering/extent_index.dart';
import '../rendering/scrollable_render_object.dart';

/// Builds an anchored-list item identified by a stable application ID.
typedef AnchoredItemBuilder<T extends Object> = Widget? Function(
    BuildContext context, int index, T itemId);

/// Resolves the sticky-header item for the first visible item.
typedef StickyHeaderIndexResolver = int? Function(int firstVisibleIndex);

/// Reports the current visible item range.
typedef VisibleRangeChanged = void Function(int firstIndex, int lastIndex);

/// A stable scroll position expressed in content identity rather than pixels.
class ListAnchor<T extends Object> {
  const ListAnchor({required this.itemId, this.localOffset = 0.0});

  final T itemId;
  final double localOffset;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ListAnchor<T> &&
            other.itemId == itemId &&
            other.localOffset == localOffset;
  }

  @override
  int get hashCode => Object.hash(itemId, localOffset);

  @override
  String toString() => 'ListAnchor($itemId, localOffset: $localOffset)';
}

abstract class _AnchoredListDelegate {
  ListAnchor<Object>? captureAnchor();
  bool restoreAnchor(ListAnchor<Object> anchor);
  bool jumpToItem(Object itemId, {double alignment, double localOffset});
  bool ensureItemVisible(Object itemId);
  bool invalidateItemExtent(Object itemId);
}

/// Controls an [AnchoredListView] using stable item IDs.
///
/// The controller also stores named anchors, which makes preserving a separate
/// message position for each chat a one-line operation.
class AnchoredListController extends ScrollController {
  AnchoredListController({
    super.initialScrollOffset,
    this.followNewItems = true,
    this.autoScrollThreshold = 2.0,
  });

  final bool followNewItems;
  final double autoScrollThreshold;

  _AnchoredListDelegate? _delegate;
  final Map<Object, ListAnchor<Object>> _savedPositions =
      <Object, ListAnchor<Object>>{};

  ListAnchor<Object>? get anchor => _delegate?.captureAnchor();

  void _attachAnchoredDelegate(_AnchoredListDelegate delegate) {
    _delegate = delegate;
  }

  void _detachAnchoredDelegate(_AnchoredListDelegate delegate) {
    if (identical(_delegate, delegate)) _delegate = null;
  }

  bool jumpToItem(
    Object itemId, {
    double alignment = 0.0,
    double localOffset = 0.0,
  }) {
    return _delegate?.jumpToItem(
          itemId,
          alignment: alignment,
          localOffset: localOffset,
        ) ??
        false;
  }

  bool ensureItemVisible(Object itemId) {
    return _delegate?.ensureItemVisible(itemId) ?? false;
  }

  /// Invalidates a cached measurement, for example after media finishes loading.
  bool invalidateItemExtent(Object itemId) {
    return _delegate?.invalidateItemExtent(itemId) ?? false;
  }

  bool savePosition(Object bucket) {
    final current = anchor;
    if (current == null) return false;
    _savedPositions[bucket] = current;
    return true;
  }

  bool restorePosition(Object bucket) {
    final saved = _savedPositions[bucket];
    if (saved == null) return false;
    return _delegate?.restoreAnchor(saved) ?? false;
  }

  void forgetPosition(Object bucket) {
    _savedPositions.remove(bucket);
  }
}

/// Selection state keyed by item ID, independent of render-object lifetime.
class AnchoredSelectionController<T extends Object> extends ChangeNotifier {
  final Set<T> _selected = <T>{};

  Set<T> get selectedItems => Set<T>.unmodifiable(_selected);
  bool get isEmpty => _selected.isEmpty;
  bool get isNotEmpty => _selected.isNotEmpty;
  int get length => _selected.length;

  bool isSelected(T itemId) => _selected.contains(itemId);

  void select(T itemId) {
    if (_selected.add(itemId)) notifyListeners();
  }

  void deselect(T itemId) {
    if (_selected.remove(itemId)) notifyListeners();
  }

  void toggle(T itemId) {
    if (!_selected.remove(itemId)) _selected.add(itemId);
    notifyListeners();
  }

  void selectOnly(T itemId) {
    if (_selected.length == 1 && _selected.contains(itemId)) return;
    _selected
      ..clear()
      ..add(itemId);
    notifyListeners();
  }

  void selectRange(List<T> orderedIds, T first, T last) {
    final firstIndex = orderedIds.indexOf(first);
    final lastIndex = orderedIds.indexOf(last);
    if (firstIndex < 0 || lastIndex < 0) return;
    final start = math.min(firstIndex, lastIndex);
    final end = math.max(firstIndex, lastIndex);
    var changed = false;
    for (var index = start; index <= end; index++) {
      changed = _selected.add(orderedIds[index]) || changed;
    }
    if (changed) notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }
}

/// A lazy, stable-ID, variable-extent viewport designed for chat history.
///
/// Unlike [ListView], this widget never derives scroll position from the set of
/// currently mounted render objects. Measurements are retained in a Fenwick
/// extent index, allowing O(log n) jumps and stable anchors across prepend,
/// append, render-object eviction, and late media relayout.
class AnchoredListView<T extends Object> extends StatefulWidget {
  const AnchoredListView.builder({
    super.key,
    required this.itemIds,
    required this.itemBuilder,
    this.controller,
    this.selectionController,
    this.reverse = false,
    this.padding,
    this.estimatedItemExtent = 1.0,
    this.cacheExtent = 10.0,
    this.maxCachedExtents = 200000,
    this.keyboardScrollable = false,
    this.hasMoreBefore = false,
    this.hasMoreAfter = false,
    this.onLoadMoreBefore,
    this.onLoadMoreAfter,
    this.loadMoreItemThreshold = 8,
    this.stickyHeaderIndexResolver,
    this.stickyHeaderBuilder,
    this.onVisibleRangeChanged,
  })  : assert(estimatedItemExtent > 0),
        assert(cacheExtent >= 0),
        assert(loadMoreItemThreshold >= 0),
        assert(
          stickyHeaderBuilder == null || stickyHeaderIndexResolver != null,
          'stickyHeaderBuilder requires stickyHeaderIndexResolver.',
        );

  final List<T> itemIds;
  final AnchoredItemBuilder<T> itemBuilder;
  final AnchoredListController? controller;
  final AnchoredSelectionController<T>? selectionController;
  final bool reverse;
  final EdgeInsets? padding;
  final double estimatedItemExtent;
  final double cacheExtent;
  final int maxCachedExtents;
  final bool keyboardScrollable;

  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final VoidCallback? onLoadMoreBefore;
  final VoidCallback? onLoadMoreAfter;
  final int loadMoreItemThreshold;

  final StickyHeaderIndexResolver? stickyHeaderIndexResolver;
  final AnchoredItemBuilder<T>? stickyHeaderBuilder;
  final VisibleRangeChanged? onVisibleRangeChanged;

  @override
  State<AnchoredListView<T>> createState() => _AnchoredListViewState<T>();
}

class _AnchoredListViewState<T extends Object>
    extends State<AnchoredListView<T>> {
  AnchoredListController? _internalController;
  int? _firstVisibleIndex;
  int? _lastVisibleIndex;
  bool _beforeRequestArmed = true;
  bool _afterRequestArmed = true;
  bool _visibleUpdateScheduled = false;
  (int, int)? _pendingVisibleRange;

  AnchoredListController get _controller =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = AnchoredListController();
    }
    widget.selectionController?.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(AnchoredListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      if (oldWidget.controller == null) {
        _internalController?.dispose();
        _internalController = null;
      }
      if (widget.controller == null) {
        _internalController = AnchoredListController();
      }
    }
    if (!identical(widget.selectionController, oldWidget.selectionController)) {
      oldWidget.selectionController?.removeListener(_handleSelectionChanged);
      widget.selectionController?.addListener(_handleSelectionChanged);
    }
    if (widget.itemIds.length != oldWidget.itemIds.length) {
      _beforeRequestArmed = true;
      _afterRequestArmed = true;
    }
  }

  @override
  void dispose() {
    widget.selectionController?.removeListener(_handleSelectionChanged);
    _internalController?.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (mounted) setState(() {});
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.arrowUp) {
      _controller.scrollUp();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      _controller.scrollDown();
      return true;
    }
    if (event.logicalKey == LogicalKey.pageUp) {
      _controller.pageUp();
      return true;
    }
    if (event.logicalKey == LogicalKey.pageDown) {
      _controller.pageDown();
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _controller.scrollToStart();
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _controller.scrollToEnd();
      return true;
    }
    return false;
  }

  void _handleVisibleRange(int firstIndex, int lastIndex) {
    _pendingVisibleRange = (firstIndex, lastIndex);
    if (_visibleUpdateScheduled) return;
    _visibleUpdateScheduled = true;

    void apply() {
      _visibleUpdateScheduled = false;
      if (!mounted) return;
      final range = _pendingVisibleRange;
      _pendingVisibleRange = null;
      if (range == null) return;
      final (first, last) = range;

      final stickyChanged = first != _firstVisibleIndex;
      _firstVisibleIndex = first;
      _lastVisibleIndex = last;
      widget.onVisibleRangeChanged?.call(first, last);

      final beforeNear = first <= widget.loadMoreItemThreshold;
      if (!beforeNear) _beforeRequestArmed = true;
      if (beforeNear &&
          widget.hasMoreBefore &&
          _beforeRequestArmed &&
          widget.onLoadMoreBefore != null) {
        _beforeRequestArmed = false;
        widget.onLoadMoreBefore!();
      }

      final afterNear =
          last >= widget.itemIds.length - 1 - widget.loadMoreItemThreshold;
      if (!afterNear) _afterRequestArmed = true;
      if (afterNear &&
          widget.hasMoreAfter &&
          _afterRequestArmed &&
          widget.onLoadMoreAfter != null) {
        _afterRequestArmed = false;
        widget.onLoadMoreAfter!();
      }

      if (stickyChanged && widget.stickyHeaderBuilder != null) {
        setState(() {});
      }
    }

    try {
      TerminalBinding.instance.addPostFrameCallback((_) => apply());
    } catch (_) {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget viewport = _AnchoredListViewport<T>(
      itemIds: widget.itemIds,
      itemBuilder: widget.itemBuilder,
      controller: _controller,
      reverse: widget.reverse,
      padding: widget.padding,
      estimatedItemExtent: widget.estimatedItemExtent,
      cacheExtent: widget.cacheExtent,
      maxCachedExtents: widget.maxCachedExtents,
      onVisibleRangeChanged: _handleVisibleRange,
    );

    final firstVisible = _firstVisibleIndex;
    final resolver = widget.stickyHeaderIndexResolver;
    final stickyBuilder = widget.stickyHeaderBuilder;
    if (firstVisible != null && resolver != null && stickyBuilder != null) {
      final stickyIndex = resolver(firstVisible);
      if (stickyIndex != null &&
          stickyIndex >= 0 &&
          stickyIndex < widget.itemIds.length) {
        viewport = Stack(
          children: <Widget>[
            viewport,
            Positioned(
              left: widget.padding?.left ?? 0.0,
              top: widget.padding?.top ?? 0.0,
              right: widget.padding?.right ?? 0.0,
              child: stickyBuilder(
                    context,
                    stickyIndex,
                    widget.itemIds[stickyIndex],
                  ) ??
                  const SizedBox.shrink(),
            ),
          ],
        );
      }
    }

    if (widget.keyboardScrollable) {
      viewport = Focusable(
        focused: true,
        onKeyEvent: _handleKeyEvent,
        child: viewport,
      );
    }
    return viewport;
  }
}

class _AnchoredListViewport<T extends Object> extends RenderObjectWidget {
  const _AnchoredListViewport({
    required this.itemIds,
    required this.itemBuilder,
    required this.controller,
    required this.reverse,
    required this.padding,
    required this.estimatedItemExtent,
    required this.cacheExtent,
    required this.maxCachedExtents,
    required this.onVisibleRangeChanged,
  });

  final List<T> itemIds;
  final AnchoredItemBuilder<T> itemBuilder;
  final AnchoredListController controller;
  final bool reverse;
  final EdgeInsets? padding;
  final double estimatedItemExtent;
  final double cacheExtent;
  final int maxCachedExtents;
  final VisibleRangeChanged onVisibleRangeChanged;

  @override
  Element createElement() => _AnchoredListViewportElement<T>(this);

  @override
  RenderAnchoredListViewport<T> createRenderObject(BuildContext context) {
    return RenderAnchoredListViewport<T>(
      itemIds: itemIds,
      controller: controller,
      reverse: reverse,
      padding: padding,
      estimatedItemExtent: estimatedItemExtent,
      cacheExtent: cacheExtent,
      maxCachedExtents: maxCachedExtents,
      onVisibleRangeChanged: onVisibleRangeChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAnchoredListViewport<T> renderObject,
  ) {
    renderObject
      ..controller = controller
      ..reverse = reverse
      ..padding = padding
      ..estimatedItemExtent = estimatedItemExtent
      ..cacheExtent = cacheExtent
      ..onVisibleRangeChanged = onVisibleRangeChanged
      ..itemIds = itemIds;
  }
}

class _AnchoredListViewportElement<T extends Object>
    extends RenderObjectElement {
  _AnchoredListViewportElement(_AnchoredListViewport<T> super.widget);

  @override
  _AnchoredListViewport<T> get widget =>
      super.widget as _AnchoredListViewport<T>;

  @override
  RenderAnchoredListViewport<T> get renderObject =>
      super.renderObject as RenderAnchoredListViewport<T>;

  final Map<T, Element> _children = <T, Element>{};
  bool _needsChildUpdate = false;
  final Set<T> _updatedThisLayout = <T>{};

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject._element = this;
  }

  @override
  void unmount() {
    renderObject._element = null;
    for (final child in _children.values.toList()) {
      if (child.mounted) {
        child.deactivate();
        child.unmount();
      }
    }
    _children.clear();
    super.unmount();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    final validIds = widget.itemIds.toSet();
    final removed =
        _children.keys.where((id) => !validIds.contains(id)).toList();
    for (final id in removed) {
      final child = _children.remove(id);
      if (child?.mounted ?? false) {
        child!.deactivate();
        child.unmount();
      }
    }
    _needsChildUpdate = true;
    _updatedThisLayout.clear();
    renderObject.markNeedsLayout();
  }

  @override
  void performRebuild() {}

  @override
  void insertRenderObjectChild(RenderObject child, dynamic slot) {}

  @override
  void moveRenderObjectChild(
    RenderObject child,
    dynamic oldSlot,
    dynamic newSlot,
  ) {}

  @override
  void removeRenderObjectChild(RenderObject child, dynamic slot) {}

  Element? buildChild(int index) {
    if (index < 0 || index >= widget.itemIds.length) return null;
    final id = widget.itemIds[index];
    final existing = _children[id];

    if (existing != null) {
      if (!_needsChildUpdate || _updatedThisLayout.contains(id)) {
        return existing;
      }
      _updatedThisLayout.add(id);
      final replacement = widget.itemBuilder(this, index, id);
      if (replacement == null) {
        existing.deactivate();
        existing.unmount();
        _children.remove(id);
        return null;
      }
      if (Widget.canUpdate(existing.widget, replacement)) {
        existing.update(replacement);
        return existing;
      }
      existing.deactivate();
      existing.unmount();
      final element = replacement.createElement();
      _children[id] = element;
      element.mount(this, id);
      return element;
    }

    final child = widget.itemBuilder(this, index, id);
    if (child == null) return null;
    final element = child.createElement();
    _children[id] = element;
    element.mount(this, id);
    if (_needsChildUpdate) _updatedThisLayout.add(id);
    return element;
  }

  void removeInvisibleChildren(Set<T> retainedIds) {
    final removed =
        _children.keys.where((id) => !retainedIds.contains(id)).toList();
    for (final id in removed) {
      final child = _children.remove(id);
      if (child?.mounted ?? false) {
        child!.deactivate();
        child.unmount();
      }
    }
  }

  void layoutComplete() {
    _needsChildUpdate = false;
    _updatedThisLayout.clear();
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    _children.values.forEach(visitor);
  }
}

class AnchoredListParentData extends ListViewParentData {
  Object? itemId;
}

class _AnchoredChildInfo<T extends Object> {
  const _AnchoredChildInfo({
    required this.itemId,
    required this.index,
    required this.renderObject,
  });

  final T itemId;
  final int index;
  final RenderObject renderObject;
}

/// Render viewport used by [AnchoredListView].
class RenderAnchoredListViewport<T extends Object> extends RenderObject
    with ScrollableRenderObjectMixin
    implements _AnchoredListDelegate {
  RenderAnchoredListViewport({
    required List<T> itemIds,
    required AnchoredListController controller,
    required bool reverse,
    required EdgeInsets? padding,
    required double estimatedItemExtent,
    required double cacheExtent,
    required int maxCachedExtents,
    required VisibleRangeChanged onVisibleRangeChanged,
  })  : _itemIds = List<T>.of(itemIds),
        _controller = controller,
        _reverse = reverse,
        _padding = padding,
        _cacheExtent = cacheExtent,
        _onVisibleRangeChanged = onVisibleRangeChanged,
        _extentIndex = ExtentIndex<T>(
          estimatedExtent: estimatedItemExtent,
          maxCachedExtents: maxCachedExtents,
        ) {
    _extentIndex.syncItems(_itemIds);
    _controller.addListener(_handleScrollUpdate);
    _controller.attach(this);
    _controller._attachAnchoredDelegate(this);
  }

  _AnchoredListViewportElement<T>? _element;
  final ExtentIndex<T> _extentIndex;
  final List<_AnchoredChildInfo<T>> _builtChildren = <_AnchoredChildInfo<T>>[];
  final List<_AnchoredChildInfo<T>> _visibleChildren =
      <_AnchoredChildInfo<T>>[];

  List<T> _itemIds;
  List<T> get itemIds => _itemIds;
  set itemIds(List<T> value) {
    if (_sameIds(_itemIds, value)) return;
    final anchorBefore = captureAnchor();
    final wasAtEnd = _isAtVisualEnd;
    final grew = value.length > _itemIds.length;
    _itemIds = List<T>.of(value);
    _extentIndex.syncItems(_itemIds);
    if (grew && wasAtEnd && _controller.followNewItems) {
      _pendingFollowEnd = true;
      _pendingAnchor = null;
    } else {
      _pendingAnchor = anchorBefore;
    }
    markNeedsLayout();
  }

  AnchoredListController _controller;
  AnchoredListController get controller => _controller;
  set controller(AnchoredListController value) {
    if (identical(value, _controller)) return;
    _controller.removeListener(_handleScrollUpdate);
    _controller.detach(this);
    _controller._detachAnchoredDelegate(this);
    _controller = value;
    _controller.addListener(_handleScrollUpdate);
    _controller.attach(this);
    _controller._attachAnchoredDelegate(this);
    markNeedsLayout();
  }

  bool _reverse;
  bool get reverse => _reverse;
  set reverse(bool value) {
    if (value == _reverse) return;
    _reverse = value;
    markNeedsLayout();
  }

  EdgeInsets? _padding;
  EdgeInsets? get padding => _padding;
  set padding(EdgeInsets? value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  double get estimatedItemExtent => _extentIndex.estimatedExtent;
  set estimatedItemExtent(double value) {
    if (value == _extentIndex.estimatedExtent) return;
    _pendingAnchor = captureAnchor();
    _extentIndex.estimatedExtent = value;
    markNeedsLayout();
  }

  double _cacheExtent;
  double get cacheExtent => _cacheExtent;
  set cacheExtent(double value) {
    if (value == _cacheExtent) return;
    _cacheExtent = value;
    markNeedsLayout();
  }

  VisibleRangeChanged _onVisibleRangeChanged;
  VisibleRangeChanged get onVisibleRangeChanged => _onVisibleRangeChanged;
  set onVisibleRangeChanged(VisibleRangeChanged value) {
    _onVisibleRangeChanged = value;
  }

  ListAnchor<Object>? _pendingAnchor;
  bool _pendingFollowEnd = false;
  double? _lastPaintedScrollOffset;

  bool get _isAtVisualEnd {
    if (_reverse) {
      return _controller.offset <=
          _controller.minScrollExtent + _controller.autoScrollThreshold;
    }
    return _controller.offset >=
        _controller.maxScrollExtent - _controller.autoScrollThreshold;
  }

  bool _sameIds(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleScrollUpdate() {
    markNeedsLayout();
  }

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! AnchoredListParentData) {
      child.parentData = AnchoredListParentData();
    }
  }

  @override
  bool handleMouseWheel(MouseEvent event) {
    if (event.button == MouseButton.wheelUp) {
      _controller.scrollBy(_reverse ? 3.0 : -3.0);
      return true;
    }
    if (event.button == MouseButton.wheelDown) {
      _controller.scrollBy(_reverse ? -3.0 : 3.0);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollUpdate);
    _controller.detach(this);
    _controller._detachAnchoredDelegate(this);
    super.dispose();
  }

  @override
  ListAnchor<Object>? captureAnchor() {
    if (_itemIds.isEmpty) return null;
    final offset =
        _controller.offset.clamp(0.0, _extentIndex.totalExtent).toDouble();
    final index = _extentIndex.indexAtOffset(offset);
    final start = _extentIndex.offsetOfIndex(index);
    return ListAnchor<Object>(
      itemId: _itemIds[index],
      localOffset: offset - start,
    );
  }

  @override
  bool restoreAnchor(ListAnchor<Object> anchor) {
    if (anchor.itemId is! T || !_extentIndex.containsId(anchor.itemId as T)) {
      return false;
    }
    _pendingAnchor = anchor;
    _pendingFollowEnd = false;
    markNeedsLayout();
    return true;
  }

  @override
  bool jumpToItem(
    Object itemId, {
    double alignment = 0.0,
    double localOffset = 0.0,
  }) {
    if (itemId is! T) return false;
    final index = _extentIndex.indexOf(itemId);
    if (index == null) return false;
    final itemOffset = _extentIndex.offsetOfIndex(index);
    final itemExtent = _extentIndex.extentAt(index);
    final target = itemOffset -
        math.max(0.0, _controller.viewportDimension - itemExtent) *
            alignment.clamp(0.0, 1.0).toDouble() +
        localOffset;
    _controller.jumpTo(target);
    return true;
  }

  @override
  bool ensureItemVisible(Object itemId) {
    if (itemId is! T) return false;
    final index = _extentIndex.indexOf(itemId);
    if (index == null) return false;
    _controller.ensureVisible(
      itemOffset: _extentIndex.offsetOfIndex(index),
      itemExtent: _extentIndex.extentAt(index),
    );
    return true;
  }

  @override
  bool invalidateItemExtent(Object itemId) {
    if (itemId is! T || !_extentIndex.containsId(itemId)) return false;
    _pendingAnchor = captureAnchor();
    final changed = _extentIndex.invalidateExtent(itemId);
    if (changed) markNeedsLayout();
    return changed;
  }

  RenderObject? _buildAndLayoutChild({
    required int index,
    required BoxConstraints childConstraints,
    required double layoutOffset,
  }) {
    final element = _element?.buildChild(index);
    if (element == null) return null;
    final renderObject = _findRenderObject(element);
    if (renderObject == null) return null;
    renderObject.layout(childConstraints, parentUsesSize: true);

    final id = _itemIds[index];
    final extent = math.max(0.000001, renderObject.size.height);
    final parentData = renderObject.parentData as AnchoredListParentData;
    parentData
      ..itemId = id
      ..index = index
      ..layoutOffset = layoutOffset
      ..extent = extent;
    _extentIndex.updateExtent(id, extent);
    return renderObject;
  }

  RenderObject? _findRenderObject(Element element) {
    RenderObject? result;
    void visitor(Element current) {
      if (result != null) return;
      if (current is RenderObjectElement) {
        result = current.renderObject;
      } else {
        current.visitChildren(visitor);
      }
    }

    visitor(element);
    if (result != null) {
      setupParentData(result!);
      if (owner != null && result!.owner != owner) {
        result!.parent = this;
        result!.attach(owner!);
      }
    }
    return result;
  }

  double _targetForAnchor(ListAnchor<Object>? anchor) {
    if (anchor == null || anchor.itemId is! T) return _controller.offset;
    final start = _extentIndex.offsetOfId(anchor.itemId as T);
    if (start == null) return _controller.offset;
    return start + anchor.localOffset;
  }

  @override
  void performLayout() {
    _builtChildren.clear();
    _visibleChildren.clear();

    final effectivePadding = padding ?? EdgeInsets.zero;
    final innerConstraints = constraints.deflate(effectivePadding);
    size = constraints.constrain(
      Size(constraints.maxWidth, constraints.maxHeight),
    );

    final viewportExtent = innerConstraints.maxHeight;
    final crossAxisExtent = innerConstraints.maxWidth;
    final childConstraints = BoxConstraints(
      minWidth: crossAxisExtent,
      maxWidth: crossAxisExtent,
      minHeight: 0.0,
      maxHeight: double.infinity,
    );

    if (_element == null || _itemIds.isEmpty || viewportExtent <= 0) {
      _controller.updateMetrics(
        minScrollExtent: 0.0,
        maxScrollExtent: 0.0,
        viewportDimension: math.max(0.0, viewportExtent),
        axisDirection: _reverse ? AxisDirection.up : AxisDirection.down,
      );
      _element?.removeInvisibleChildren(<T>{});
      _element?.layoutComplete();
      return;
    }

    final anchorBefore = _pendingAnchor ?? captureAnchor();
    var layoutScrollOffset = _controller.offset;
    if (_pendingFollowEnd) {
      layoutScrollOffset = _reverse
          ? 0.0
          : math.max(0.0, _extentIndex.totalExtent - viewportExtent);
    } else if (_pendingAnchor != null) {
      layoutScrollOffset = _targetForAnchor(_pendingAnchor);
    }

    final cacheStart = math.max(0.0, layoutScrollOffset - _cacheExtent);
    final cacheEnd = layoutScrollOffset + viewportExtent + _cacheExtent;
    var index = _extentIndex.indexAtOffset(cacheStart);
    var currentPosition = _extentIndex.offsetOfIndex(index);
    final retainedIds = <T>{};

    while (index < _itemIds.length && currentPosition < cacheEnd) {
      final id = _itemIds[index];
      final renderObject = _buildAndLayoutChild(
        index: index,
        childConstraints: childConstraints,
        layoutOffset: currentPosition,
      );
      if (renderObject == null) break;

      final parentData = renderObject.parentData as AnchoredListParentData;
      final extent = parentData.extent ?? renderObject.size.height;
      _builtChildren.add(
        _AnchoredChildInfo<T>(
          itemId: id,
          index: index,
          renderObject: renderObject,
        ),
      );
      retainedIds.add(id);
      currentPosition += extent;
      index++;
    }

    final totalExtent = _extentIndex.totalExtent;
    final maxExtent = math.max(0.0, totalExtent - viewportExtent);
    _controller.updateMetrics(
      minScrollExtent: 0.0,
      maxScrollExtent: maxExtent,
      viewportDimension: viewportExtent,
      axisDirection: _reverse ? AxisDirection.up : AxisDirection.down,
    );

    if (_pendingFollowEnd) {
      _controller.correctTo(_reverse ? 0.0 : maxExtent);
    } else {
      _controller.correctTo(_targetForAnchor(anchorBefore));
    }
    _pendingFollowEnd = false;
    _pendingAnchor = null;

    final finalOffset = _controller.offset;
    for (final child in _builtChildren) {
      final parentData =
          child.renderObject.parentData as AnchoredListParentData;
      final start = parentData.layoutOffset ?? 0.0;
      final extent = parentData.extent ?? child.renderObject.size.height;
      if (start + extent > finalOffset &&
          start < finalOffset + viewportExtent) {
        _visibleChildren.add(child);
      }

      var childPosition = start - finalOffset;
      if (_reverse) {
        childPosition = viewportExtent - childPosition - extent;
      }
      parentData.offset = Offset(
        effectivePadding.left,
        effectivePadding.top + childPosition,
      );
    }

    _element?.removeInvisibleChildren(retainedIds);
    _element?.layoutComplete();

    if (_visibleChildren.isNotEmpty) {
      _onVisibleRangeChanged(
        _visibleChildren.first.index,
        _visibleChildren.last.index,
      );
    }
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    final effectivePadding = padding ?? EdgeInsets.zero;
    final previousOffset = _lastPaintedScrollOffset;
    final currentOffset = _controller.offset;
    if (previousOffset != null) {
      final rawDelta = currentOffset - previousOffset;
      final roundedDelta = rawDelta.round();
      final viewportHeight = size.height.floor();
      if (roundedDelta != 0 &&
          (rawDelta - roundedDelta).abs() < 0.0001 &&
          roundedDelta.abs() < viewportHeight) {
        owner?.requestTerminalScroll(
          TerminalScrollRequest(
            left: offset.dx.round(),
            top: offset.dy.round(),
            width: size.width.round(),
            height: viewportHeight,
            lines: _reverse ? -roundedDelta : roundedDelta,
          ),
        );
      }
    }
    _lastPaintedScrollOffset = currentOffset;

    final clipped = canvas.clip(
      Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
    );
    final viewportExtent =
        size.height - effectivePadding.top - effectivePadding.bottom;

    for (final child in _visibleChildren) {
      final parentData =
          child.renderObject.parentData as AnchoredListParentData;
      final start = parentData.layoutOffset ?? 0.0;
      final extent = parentData.extent ?? child.renderObject.size.height;
      var childPosition = start - _controller.offset;
      if (_reverse) {
        childPosition = viewportExtent - childPosition - extent;
      }
      final childOffset = Offset(
        offset.dx + effectivePadding.left,
        offset.dy + effectivePadding.top + childPosition,
      );
      parentData.offset = childOffset - offset;
      child.renderObject.paint(clipped, childOffset);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    for (final child in _builtChildren) {
      visitor(child.renderObject);
    }
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    if (!Rect.fromLTWH(0, 0, size.width, size.height).contains(position)) {
      return false;
    }
    final hitChild = hitTestChildren(result, position: position);
    if (hitChild || hitTestSelf(position)) {
      result.add(this);
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    for (var i = _visibleChildren.length - 1; i >= 0; i--) {
      final child = _visibleChildren[i];
      final parentData =
          child.renderObject.parentData as AnchoredListParentData;
      final childOffset = parentData.offset;
      final bounds = Rect.fromLTWH(
        childOffset.dx,
        childOffset.dy,
        child.renderObject.size.width,
        child.renderObject.size.height,
      );
      if (!bounds.contains(position)) continue;
      if (child.renderObject.hitTest(
        result,
        position: position - childOffset,
      )) {
        return true;
      }
    }
    return false;
  }
}
