/// Mouse button types
enum MouseButton {
  left,
  middle,
  right,
  wheelUp,
  wheelDown,
}

/// Mouse event for terminal interactions
class MouseEvent {
  final MouseButton button;
  final int x; // Column position (0-based)
  final int y; // Row position (0-based)
  final bool pressed; // true for press, false for release
  final bool isMotion; // true for motion events (drag), false for press/release

  /// The set of mouse buttons currently held down (enriched by [MouseTracker]).
  final Set<MouseButton> buttons;

  const MouseEvent({
    required this.button,
    required this.x,
    required this.y,
    required this.pressed,
    this.isMotion = false,
    this.buttons = const {},
  });

  /// Whether the primary (left) button is currently held down.
  bool get isPrimaryButtonDown => buttons.contains(MouseButton.left);

  /// Whether the secondary (right) button is currently held down.
  bool get isSecondaryButtonDown => buttons.contains(MouseButton.right);

  /// Whether the middle button is currently held down.
  bool get isMiddleButtonDown => buttons.contains(MouseButton.middle);

  bool isButtonDown(MouseButton value) => buttons.contains(value);

  MouseEvent copyWith({
    MouseButton? button,
    int? x,
    int? y,
    bool? pressed,
    bool? isMotion,
    Set<MouseButton>? buttons,
  }) {
    return MouseEvent(
      button: button ?? this.button,
      x: x ?? this.x,
      y: y ?? this.y,
      pressed: pressed ?? this.pressed,
      isMotion: isMotion ?? this.isMotion,
      buttons: buttons ?? this.buttons,
    );
  }

  @override
  String toString() =>
      'MouseEvent($button at $x,$y pressed=$pressed${isMotion ? ' (motion)' : ''}${buttons.isNotEmpty ? ' buttons=$buttons' : ''})';
}
