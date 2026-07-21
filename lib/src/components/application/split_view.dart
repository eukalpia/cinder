import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// Controls the divider position of a [SplitView].
class SplitViewController extends ChangeNotifier {
  SplitViewController({
    double ratio = 0.5,
    this.minRatio = 0.05,
    this.maxRatio = 0.95,
  }) : assert(minRatio >= 0 && minRatio < maxRatio),
       assert(maxRatio <= 1),
       _ratio = ratio.clamp(minRatio, maxRatio);

  final double minRatio;
  final double maxRatio;
  double _ratio;

  double get ratio => _ratio;

  set ratio(double value) {
    final next = value.clamp(minRatio, maxRatio);
    if (_ratio == next) return;
    _ratio = next;
    notifyListeners();
  }

  void nudge(double delta) => ratio = _ratio + delta;
  void reset([double value = 0.5]) => ratio = value;
}

/// A two-pane layout with keyboard and mouse-resizable divider.
class SplitView extends StatefulWidget {
  const SplitView({
    super.key,
    required this.first,
    required this.second,
    this.axis = Axis.horizontal,
    this.controller,
    this.initialRatio = 0.5,
    this.dividerExtent = 1.0,
    this.minFirstExtent = 1.0,
    this.minSecondExtent = 1.0,
    this.dividerColor,
    this.dividerCharacter,
    this.autofocus = false,
    this.keyboardStep = 0.05,
    this.onChanged,
  }) : assert(initialRatio > 0 && initialRatio < 1),
       assert(dividerExtent >= 1),
       assert(minFirstExtent >= 0),
       assert(minSecondExtent >= 0),
       assert(keyboardStep > 0);

  final Widget first;
  final Widget second;
  final Axis axis;
  final SplitViewController? controller;
  final double initialRatio;
  final double dividerExtent;
  final double minFirstExtent;
  final double minSecondExtent;
  final Color? dividerColor;
  final String? dividerCharacter;
  final bool autofocus;
  final double keyboardStep;
  final ValueChanged<double>? onChanged;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  SplitViewController? _ownedController;
  late SplitViewController _controller;
  double _availableExtent = 0;
  double? _lastDragCoordinate;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  void _attachController() {
    _ownedController = widget.controller == null
        ? SplitViewController(ratio: widget.initialRatio)
        : null;
    _controller = widget.controller ?? _ownedController!;
    _controller.addListener(_handleControllerChanged);
  }

  void _detachController() {
    _controller.removeListener(_handleControllerChanged);
    _ownedController?.dispose();
    _ownedController = null;
  }

  @override
  void didUpdateWidget(SplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _detachController();
      _attachController();
    }
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(_controller.ratio);
    if (mounted) setState(() {});
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (widget.axis == Axis.horizontal) {
      if (event.logicalKey == LogicalKey.arrowLeft) {
        _controller.nudge(-widget.keyboardStep);
        return true;
      }
      if (event.logicalKey == LogicalKey.arrowRight) {
        _controller.nudge(widget.keyboardStep);
        return true;
      }
    } else {
      if (event.logicalKey == LogicalKey.arrowUp) {
        _controller.nudge(-widget.keyboardStep);
        return true;
      }
      if (event.logicalKey == LogicalKey.arrowDown) {
        _controller.nudge(widget.keyboardStep);
        return true;
      }
    }
    if (event.logicalKey == LogicalKey.home) {
      _controller.ratio = _minimumRatio();
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _controller.ratio = _maximumRatio();
      return true;
    }
    return false;
  }

  double _minimumRatio() {
    if (_availableExtent <= 0) return _controller.minRatio;
    return math.max(
      _controller.minRatio,
      widget.minFirstExtent / _availableExtent,
    );
  }

  double _maximumRatio() {
    if (_availableExtent <= 0) return _controller.maxRatio;
    return math.min(
      _controller.maxRatio,
      1 - widget.minSecondExtent / _availableExtent,
    );
  }

  void _beginDrag(TapDownDetails details) {
    _lastDragCoordinate = widget.axis == Axis.horizontal
        ? details.globalPosition.dx
        : details.globalPosition.dy;
  }

  void _endDrag(TapUpDetails details) {
    _lastDragCoordinate = null;
  }

  void _handleDividerHover(MouseEvent event) {
    if (!(event.pressed || event.isPrimaryButtonDown)) {
      _lastDragCoordinate = null;
      return;
    }
    final coordinate = widget.axis == Axis.horizontal
        ? event.x.toDouble()
        : event.y.toDouble();
    final previous = _lastDragCoordinate;
    _lastDragCoordinate = coordinate;
    if (previous == null || _availableExtent <= 0) return;
    _controller.ratio += (coordinate - previous) / _availableExtent;
  }

  Widget _buildDivider() {
    final character =
        widget.dividerCharacter ?? (widget.axis == Axis.horizontal ? '│' : '─');
    final color = widget.dividerColor ?? Colors.grey;
    final divider = Container(
      width: widget.axis == Axis.horizontal ? widget.dividerExtent : null,
      height: widget.axis == Axis.vertical ? widget.dividerExtent : null,
      alignment: Alignment.center,
      child: Text(
        character,
        style: TextStyle(color: color),
        overflow: TextOverflow.clip,
      ),
    );

    return MouseRegion(
      onHover: _handleDividerHover,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _beginDrag,
        onTapUp: _endDrag,
        onTapCancel: () => _lastDragCoordinate = null,
        onDoubleTap: _controller.reset,
        child: divider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalExtent = widget.axis == Axis.horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          final finiteTotal = totalExtent.isFinite ? totalExtent : 0.0;
          _availableExtent = math.max(0, finiteTotal - widget.dividerExtent);
          final minRatio = _minimumRatio();
          final maxRatio = math.max(minRatio, _maximumRatio());
          final ratio = _controller.ratio.clamp(minRatio, maxRatio);
          final firstExtent = _availableExtent * ratio;

          if (widget.axis == Axis.horizontal) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: firstExtent, child: widget.first),
                _buildDivider(),
                Expanded(child: widget.second),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: firstExtent, child: widget.first),
              _buildDivider(),
              Expanded(child: widget.second),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }
}

/// Applies minimum and maximum extent constraints to a split pane.
class ResizablePane extends StatelessWidget {
  const ResizablePane({
    super.key,
    required this.child,
    this.axis = Axis.horizontal,
    this.minExtent = 0,
    this.maxExtent = double.infinity,
  }) : assert(minExtent >= 0),
       assert(maxExtent >= minExtent);

  final Widget child;
  final Axis axis;
  final double minExtent;
  final double maxExtent;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: axis == Axis.horizontal
          ? BoxConstraints(minWidth: minExtent, maxWidth: maxExtent)
          : BoxConstraints(minHeight: minExtent, maxHeight: maxExtent),
      child: child,
    );
  }
}
