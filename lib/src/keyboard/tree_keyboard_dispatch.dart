import '../components/block_focus.dart';
import '../components/focusable.dart';
import '../framework/framework.dart';
import '../navigation/render_theater.dart';
import 'keyboard_event.dart';

/// Routes legacy focused listeners identically in native and test bindings.
/// Overlay input belongs to the top entry; ignored keys may bubble to the
/// navigator but must never reach covered routes.
bool dispatchKeyboardToTree(
  Element element,
  KeyboardEvent event, {
  bool Function(Element, KeyboardEvent)? onUnhandled,
}) {
  if (element is BlockFocusElement && element.isBlocking) return true;

  if (element is MultiChildRenderObjectElement &&
      element.renderObject is RenderTheater &&
      element.children.isNotEmpty) {
    return dispatchKeyboardToTree(
      element.children.last,
      event,
      onUnhandled: onUnhandled,
    );
  }

  var handled = false;
  element.visitChildren((child) {
    if (!handled) {
      handled = dispatchKeyboardToTree(child, event, onUnhandled: onUnhandled);
    }
  });
  if (!handled && element is FocusableElement) {
    handled = element.handleKeyEvent(event);
  }
  return handled || (onUnhandled?.call(element, event) ?? false);
}
