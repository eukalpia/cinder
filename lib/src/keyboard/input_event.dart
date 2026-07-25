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

/// Lifecycle stage of terminal text composition.
enum CompositionStage { start, update, commit, end }

/// Pre-edit or committed text produced by an input method editor.
class CompositionInputEvent extends TextInputEvent {
  const CompositionInputEvent(
    super.text, {
    required this.stage,
    this.selectionStart,
    this.selectionEnd,
  });

  final CompositionStage stage;
  final int? selectionStart;
  final int? selectionEnd;

  bool get isCommit => stage == CompositionStage.commit;
}
