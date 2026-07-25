import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';

/// A callback that handles keyboard events with character data.
/// Returns true if the event was handled, false otherwise.
typedef KeyEventHandler = bool Function(KeyboardEvent event);

/// A widget that can receive keyboard focus and handle keyboard events.
///
/// This widget wraps its child and, when focused, receives keyboard events
/// from the framework. Events that are not handled (onKeyEvent returns false) will
/// bubble up to parent Focusable components.
///
/// Example:
/// ```dart
/// Focusable(
///   focused: hasFocus,
///   onKeyEvent: (event) {
///     if (event.logicalKey == LogicalKey.enter) {
///       // Handle enter key
///       return true;
///     }
///     if (event.character != null) {
///       // Handle character input
///       insertText(event.character!);
///       return true;
///     }
///     return false; // Let unhandled keys bubble up
///   },
///   child: Container(child: Text('Press Enter')),
/// )
/// ```
class Focusable extends StatelessWidget {
  const Focusable({
    super.key,
    required this.focused,
    required this.onKeyEvent,
    required this.child,
  });

  /// Whether this widget currently has focus.
  final bool focused;

  /// Callback to handle keyboard events with character data.
  /// Should return true if the event was handled, false otherwise.
  final KeyEventHandler onKeyEvent;

  /// The child widget to wrap.
  final Widget child;

  @override
  FocusableElement createElement() => FocusableElement(this);

  @override
  Widget build(BuildContext context) => child;
}

/// Element for the Focusable widget.
class FocusableElement extends StatelessElement {
  FocusableElement(Focusable super.widget);

  @override
  Focusable get widget => super.widget as Focusable;

  /// Handle a keyboard event if this element is focused.
  bool handleKeyEvent(KeyboardEvent event) {
    if (!widget.focused) {
      return false;
    }

    final handled = widget.onKeyEvent(event);
    return handled;
  }
}
