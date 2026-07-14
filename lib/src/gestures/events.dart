import '../framework/framework.dart';
import '../keyboard/mouse_event.dart';

/// Details for a pointer down that may become a tap.
class TapDownDetails {
  const TapDownDetails({
    required this.globalPosition,
    required this.localPosition,
    this.button = MouseButton.left,
    this.buttons = const <MouseButton>{},
  });

  final Offset globalPosition;
  final Offset localPosition;
  final MouseButton button;
  final Set<MouseButton> buttons;
}

/// Details for a completed pointer up.
class TapUpDetails {
  const TapUpDetails({
    required this.globalPosition,
    required this.localPosition,
    this.button = MouseButton.left,
    this.buttons = const <MouseButton>{},
  });

  final Offset globalPosition;
  final Offset localPosition;
  final MouseButton button;
  final Set<MouseButton> buttons;
}

/// Details for the beginning of a button drag.
class DragStartDetails {
  const DragStartDetails({
    required this.globalPosition,
    required this.localPosition,
    required this.button,
    required this.buttons,
  });

  final Offset globalPosition;
  final Offset localPosition;
  final MouseButton button;
  final Set<MouseButton> buttons;
}

/// Details for a drag update.
class DragUpdateDetails {
  const DragUpdateDetails({
    required this.globalPosition,
    required this.localPosition,
    required this.delta,
    required this.button,
    required this.buttons,
  });

  final Offset globalPosition;
  final Offset localPosition;
  final Offset delta;
  final MouseButton button;
  final Set<MouseButton> buttons;
}

/// Details for the end of a button drag.
class DragEndDetails {
  const DragEndDetails({
    required this.globalPosition,
    required this.localPosition,
    required this.button,
    required this.buttons,
  });

  final Offset globalPosition;
  final Offset localPosition;
  final MouseButton button;
  final Set<MouseButton> buttons;
}

/// Details for long press start events.
class LongPressStartDetails {
  const LongPressStartDetails({
    required this.globalPosition,
    required this.localPosition,
  });

  final Offset globalPosition;
  final Offset localPosition;
}

/// Details for long press end events.
class LongPressEndDetails {
  const LongPressEndDetails({
    required this.globalPosition,
    required this.localPosition,
  });

  final Offset globalPosition;
  final Offset localPosition;
}

typedef GestureTapDownCallback = void Function(TapDownDetails details);
typedef GestureTapUpCallback = void Function(TapUpDetails details);
typedef GestureTapCallback = void Function();
typedef GestureTapCancelCallback = void Function();
typedef GestureDragStartCallback = void Function(DragStartDetails details);
typedef GestureDragUpdateCallback = void Function(DragUpdateDetails details);
typedef GestureDragEndCallback = void Function(DragEndDetails details);
typedef GesturePointerCallback = void Function(MouseEvent event);
typedef GestureLongPressCallback = void Function();
typedef GestureLongPressStartCallback = void Function(
  LongPressStartDetails details,
);
typedef GestureLongPressEndCallback = void Function(
  LongPressEndDetails details,
);
