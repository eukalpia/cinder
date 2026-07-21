import 'package:cinder/cinder.dart';

/// A production-oriented, lazily built list for large or unbounded data sets.
///
/// This is the explicit virtualized facade over Cinder's lazy [ListView]
/// renderer. Only visible children plus [cacheExtent] are kept mounted.
class VirtualListView extends StatelessWidget {
  const VirtualListView.builder({
    super.key,
    required this.itemBuilder,
    this.itemCount,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.itemExtent,
    this.cacheExtent = 5.0,
    this.keyboardScrollable = false,
  }) : separatorBuilder = null;

  const VirtualListView.separated({
    super.key,
    required this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    this.itemCount,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.cacheExtent = 5.0,
    this.keyboardScrollable = false,
  }) : itemExtent = null;

  /// Creates an unbounded virtual list. The builder ends the list by returning
  /// null.
  const VirtualListView.infinite({
    super.key,
    required this.itemBuilder,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.itemExtent,
    this.cacheExtent = 5.0,
    this.keyboardScrollable = false,
  }) : itemCount = null,
       separatorBuilder = null;

  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final int? itemCount;
  final ScrollController? controller;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsets? padding;
  final double? itemExtent;
  final double cacheExtent;
  final bool keyboardScrollable;

  @override
  Widget build(BuildContext context) {
    final separator = separatorBuilder;
    if (separator != null) {
      return ListView.separated(
        controller: controller,
        scrollDirection: scrollDirection,
        reverse: reverse,
        padding: padding,
        lazy: true,
        cacheExtent: cacheExtent,
        keyboardScrollable: keyboardScrollable,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: separator,
      );
    }

    return ListView.builder(
      controller: controller,
      scrollDirection: scrollDirection,
      reverse: reverse,
      padding: padding,
      itemExtent: itemExtent,
      lazy: true,
      cacheExtent: cacheExtent,
      keyboardScrollable: keyboardScrollable,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// A scroll controller with exact index operations for fixed-extent virtual
/// lists.
class VirtualListController extends ScrollController {
  VirtualListController({super.initialScrollOffset, this.itemExtent})
    : assert(itemExtent == null || itemExtent > 0);

  final double? itemExtent;

  void jumpToIndex(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must be non-negative');
    }
    final extent = itemExtent;
    if (extent == null) {
      ensureIndexVisible(index: index);
      return;
    }
    jumpTo(index * extent);
  }

  void ensureVirtualIndexVisible(int index) {
    if (index < 0) return;
    final extent = itemExtent;
    if (extent == null) {
      ensureIndexVisible(index: index);
      return;
    }
    ensureVisible(itemOffset: index * extent, itemExtent: extent);
  }
}
