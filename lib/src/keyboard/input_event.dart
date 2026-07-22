import '../size.dart';
import 'keyboard_event.dart';
import 'mouse_event.dart';

/// Base class for normalized terminal input events.
abstract class InputEvent {
  const InputEvent();
}

/// A physical or logical keyboard action.
class KeyboardInputEvent extends InputEvent {
  const KeyboardInputEvent(this.event);

  final KeyboardEvent event;
}

/// Text entered through a terminal input method.
///
/// This event represents text rather than a physical key and is suitable for
/// IME commits, synthetic text injection, and terminal protocols that provide a
/// committed string directly.
class TextInputEvent extends InputEvent {
  const TextInputEvent(this.text);

  final String text;
}

/// A mouse button, motion, or wheel action.
class MouseInputEvent extends InputEvent {
  const MouseInputEvent(this.event);

  final MouseEvent event;
}

/// Text received through bracketed paste mode.
class PasteInputEvent extends TextInputEvent {
  const PasteInputEvent(super.text);
}

/// A change in the terminal viewport size.
class ResizeInputEvent extends InputEvent {
  const ResizeInputEvent({required this.previousSize, required this.size});

  final Size? previousSize;
  final Size size;
}

/// A terminal focus-in or focus-out notification.
class TerminalFocusInputEvent extends InputEvent {
  const TerminalFocusInputEvent({required this.hasFocus});

  final bool hasFocus;
}
