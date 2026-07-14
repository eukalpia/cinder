import '../framework/framework.dart';
import '../gestures/events.dart';
import '../gestures/hit_test.dart';
import '../gestures/long_press.dart';
import '../gestures/tap.dart';
import '../keyboard/mouse_event.dart';
import '../rendering/mouse_tracker.dart';
import 'package:cinder/src/rendering/mouse_region.dart';

/// Detects taps, button-specific taps, and button-aware drag gestures.
class GestureDetector extends StatefulWidget {
  const GestureDetector({
    super.key,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onMiddleTap,
    this.onMiddleTapDown,
    this.onMiddleTapUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.behavior = HitTestBehavior.deferToChild,
    this.child,
  });

  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapCallback? onDoubleTap;

  final GestureTapCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureTapCallback? onMiddleTap;
  final GestureTapDownCallback? onMiddleTapDown;
  final GestureTapUpCallback? onMiddleTapUp;

  /// Button-aware drag callbacks. They work for left, middle, and right drag.
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  /// Raw pointer callbacks with the complete currently-held button set.
  final GesturePointerCallback? onPointerDown;
  final GesturePointerCallback? onPointerMove;
  final GesturePointerCallback? onPointerUp;

  final GestureLongPressCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final HitTestBehavior behavior;
  final Widget? child;

  @override
  State<GestureDetector> createState() => _GestureDetectorState();
}

class _PointerSequence {
  _PointerSequence(this.downPosition);

  final Offset downPosition;
  Offset? lastPosition;
  bool dragging = false;
}

class _GestureDetectorState extends State<GestureDetector> {
  TapGestureRecognizer? _tapRecognizer;
  DoubleTapGestureRecognizer? _doubleTapRecognizer;
  LongPressGestureRecognizer? _longPressRecognizer;
  final Map<MouseButton, _PointerSequence> _sequences =
      <MouseButton, _PointerSequence>{};

  static const double _tapSlop = 2.0;

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(GestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRecognizers();
  }

  @override
  void dispose() {
    _tapRecognizer?.dispose();
    _doubleTapRecognizer?.dispose();
    _longPressRecognizer?.dispose();
    super.dispose();
  }

  void _syncRecognizers() {
    if (widget.onTap != null ||
        widget.onTapDown != null ||
        widget.onTapUp != null ||
        widget.onTapCancel != null) {
      _tapRecognizer ??= TapGestureRecognizer();
      _tapRecognizer!
        ..onTap = widget.onTap
        ..onTapDown = widget.onTapDown
        ..onTapUp = widget.onTapUp
        ..onTapCancel = widget.onTapCancel;
    } else {
      _tapRecognizer?.dispose();
      _tapRecognizer = null;
    }

    if (widget.onDoubleTap != null) {
      _doubleTapRecognizer ??= DoubleTapGestureRecognizer();
      _doubleTapRecognizer!.onDoubleTap = widget.onDoubleTap;
    } else {
      _doubleTapRecognizer?.dispose();
      _doubleTapRecognizer = null;
    }

    if (widget.onLongPress != null ||
        widget.onLongPressStart != null ||
        widget.onLongPressEnd != null) {
      _longPressRecognizer ??= LongPressGestureRecognizer();
      _longPressRecognizer!
        ..onLongPress = widget.onLongPress
        ..onLongPressStart = widget.onLongPressStart
        ..onLongPressEnd = widget.onLongPressEnd;
    } else {
      _longPressRecognizer?.dispose();
      _longPressRecognizer = null;
    }
  }

  Offset _position(MouseEvent event) =>
      Offset(event.x.toDouble(), event.y.toDouble());

  TapDownDetails _tapDownDetails(MouseEvent event, Offset position) {
    return TapDownDetails(
      globalPosition: position,
      localPosition: position,
      button: event.button,
      buttons: event.buttons,
    );
  }

  TapUpDetails _tapUpDetails(MouseEvent event, Offset position) {
    return TapUpDetails(
      globalPosition: position,
      localPosition: position,
      button: event.button,
      buttons: event.buttons,
    );
  }

  void _handlePointerDown(MouseEvent event) {
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      return;
    }
    final position = _position(event);
    _sequences[event.button] = _PointerSequence(position)
      ..lastPosition = position;
    widget.onPointerDown?.call(event);

    switch (event.button) {
      case MouseButton.left:
        _tapRecognizer?.addPointer(event, position);
        _doubleTapRecognizer?.addPointer(event, position);
        _longPressRecognizer?.addPointer(event, position);
        break;
      case MouseButton.right:
        widget.onSecondaryTapDown?.call(_tapDownDetails(event, position));
        break;
      case MouseButton.middle:
        widget.onMiddleTapDown?.call(_tapDownDetails(event, position));
        break;
      case MouseButton.wheelUp:
      case MouseButton.wheelDown:
        break;
    }
  }

  void _handlePointerMove(MouseEvent event) {
    final position = _position(event);
    widget.onPointerMove?.call(event);

    final primary = _sequences[MouseButton.left];
    if (primary != null) {
      _tapRecognizer?.handlePointerMove(event, position);
      _doubleTapRecognizer?.handlePointerMove(event, position);
      _longPressRecognizer?.handlePointerMove(event, position);
    }

    for (final entry in _sequences.entries.toList(growable: false)) {
      final sequence = entry.value;
      final previous = sequence.lastPosition ?? sequence.downPosition;
      final delta = position - previous;
      if (delta == Offset.zero) continue;

      if (!sequence.dragging) {
        sequence.dragging = true;
        widget.onDragStart?.call(
          DragStartDetails(
            globalPosition: position,
            localPosition: position,
            button: entry.key,
            buttons: event.buttons,
          ),
        );
      }
      widget.onDragUpdate?.call(
        DragUpdateDetails(
          globalPosition: position,
          localPosition: position,
          delta: delta,
          button: entry.key,
          buttons: event.buttons,
        ),
      );
      sequence.lastPosition = position;
    }
  }

  void _handlePointerUp(MouseEvent event) {
    final position = _position(event);
    final sequence = _sequences.remove(event.button);
    widget.onPointerUp?.call(event);

    if (sequence?.dragging ?? false) {
      widget.onDragEnd?.call(
        DragEndDetails(
          globalPosition: position,
          localPosition: position,
          button: event.button,
          buttons: event.buttons,
        ),
      );
    }

    switch (event.button) {
      case MouseButton.left:
        _tapRecognizer?.handlePointerUp(event, position);
        _doubleTapRecognizer?.handlePointerUp(event, position);
        _longPressRecognizer?.handlePointerUp(event, position);
        break;
      case MouseButton.right:
        widget.onSecondaryTapUp?.call(_tapUpDetails(event, position));
        if (_isTap(sequence, position)) widget.onSecondaryTap?.call();
        break;
      case MouseButton.middle:
        widget.onMiddleTapUp?.call(_tapUpDetails(event, position));
        if (_isTap(sequence, position)) widget.onMiddleTap?.call();
        break;
      case MouseButton.wheelUp:
      case MouseButton.wheelDown:
        break;
    }
  }

  bool _isTap(_PointerSequence? sequence, Offset position) {
    if (sequence == null || sequence.dragging) return false;
    return (position.dx - sequence.downPosition.dx).abs() <= _tapSlop &&
        (position.dy - sequence.downPosition.dy).abs() <= _tapSlop;
  }

  @override
  Widget build(BuildContext context) {
    return _GestureDetectorMouseRegion(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerMove: _handlePointerMove,
      behavior: widget.behavior,
      child: widget.child,
    );
  }
}

class _GestureDetectorMouseRegion extends SingleChildRenderObjectWidget {
  const _GestureDetectorMouseRegion({
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerMove,
    required this.behavior,
    super.child,
  });

  final void Function(MouseEvent) onPointerDown;
  final void Function(MouseEvent) onPointerUp;
  final void Function(MouseEvent) onPointerMove;
  final HitTestBehavior behavior;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGestureDetector(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerMove: onPointerMove,
      behavior: behavior,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGestureDetector renderObject,
  ) {
    renderObject
      ..onPointerDown = onPointerDown
      ..onPointerUp = onPointerUp
      ..onPointerMove = onPointerMove
      ..behavior = behavior;
  }
}

class _RenderGestureDetector extends RenderMouseRegion {
  _RenderGestureDetector({
    required void Function(MouseEvent) onPointerDown,
    required void Function(MouseEvent) onPointerUp,
    required void Function(MouseEvent) onPointerMove,
    required HitTestBehavior behavior,
  }) : _onPointerDown = onPointerDown,
       _onPointerUp = onPointerUp,
       _onPointerMove = onPointerMove,
       _behavior = behavior,
       super(opaque: behavior == HitTestBehavior.opaque);

  void Function(MouseEvent) _onPointerDown;
  void Function(MouseEvent) get onPointerDown => _onPointerDown;
  set onPointerDown(void Function(MouseEvent) value) {
    if (_onPointerDown == value) return;
    _onPointerDown = value;
    _updateGestureAnnotation();
  }

  void Function(MouseEvent) _onPointerUp;
  void Function(MouseEvent) get onPointerUp => _onPointerUp;
  set onPointerUp(void Function(MouseEvent) value) {
    if (_onPointerUp == value) return;
    _onPointerUp = value;
    _updateGestureAnnotation();
  }

  void Function(MouseEvent) _onPointerMove;
  void Function(MouseEvent) get onPointerMove => _onPointerMove;
  set onPointerMove(void Function(MouseEvent) value) {
    if (_onPointerMove == value) return;
    _onPointerMove = value;
    _updateGestureAnnotation();
  }

  HitTestBehavior _behavior;
  HitTestBehavior get behavior => _behavior;
  set behavior(HitTestBehavior value) {
    if (_behavior == value) return;
    _behavior = value;
    opaque = value == HitTestBehavior.opaque;
  }

  MouseTrackerAnnotation? _gestureAnnotation;
  final Set<MouseButton> _pressedButtons = <MouseButton>{};

  @override
  MouseTrackerAnnotation? get annotation =>
      _gestureAnnotation ?? super.annotation;

  void _syncButtonTransitions(MouseEvent event) {
    final target = Set<MouseButton>.of(event.buttons)
      ..remove(MouseButton.wheelUp)
      ..remove(MouseButton.wheelDown);

    for (final button in target.difference(_pressedButtons)) {
      _onPointerDown(
        event.copyWith(button: button, pressed: true, buttons: target),
      );
    }
    for (final button in _pressedButtons.difference(target)) {
      _onPointerUp(
        event.copyWith(button: button, pressed: false, buttons: target),
      );
    }

    _pressedButtons
      ..clear()
      ..addAll(target);
  }

  void _updateGestureAnnotation() {
    _gestureAnnotation = MouseTrackerAnnotation(
      onEnter: _syncButtonTransitions,
      onExit: (event) {
        if (_pressedButtons.isEmpty) return;
        final released = Set<MouseButton>.of(_pressedButtons);
        _pressedButtons.clear();
        for (final button in released) {
          _onPointerUp(
            event.copyWith(
              button: button,
              pressed: false,
              buttons: const <MouseButton>{},
            ),
          );
        }
      },
      onHover: (event) {
        _syncButtonTransitions(event);
        if (event.button != MouseButton.wheelUp &&
            event.button != MouseButton.wheelDown) {
          _onPointerMove(event);
        }
      },
      renderObject: this,
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateGestureAnnotation();
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
