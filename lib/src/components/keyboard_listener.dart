import '../framework/framework.dart';
import '../keyboard/logical_key.dart';
import '../keyboard/keyboard_event.dart';
import 'focusable.dart';

/// A simple keyboard listener that converts keyboard events to logical keys.
///
/// Unlike the lower-level [Focusable], a [KeyboardListener] is active by
/// default. Set [autofocus] to false when focus is managed explicitly by a
/// parent widget or focus controller.
class KeyboardListener extends StatelessWidget {
  const KeyboardListener({
    super.key,
    required this.onKeyEvent,
    required this.child,
    this.autofocus = true,
  });

  final bool Function(LogicalKey key)? onKeyEvent;
  final Widget child;

  /// Whether this listener participates in keyboard dispatch immediately.
  ///
  /// Defaults to true because [KeyboardListener] is the convenient global-key
  /// wrapper. Use [Focusable] directly for manually controlled focus.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      focused: autofocus,
      onKeyEvent: (KeyboardEvent event) {
        return onKeyEvent?.call(event.logicalKey) ?? false;
      },
      child: child,
    );
  }
}
