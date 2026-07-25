import 'input_event.dart';

/// Traversal phase used by [InputRouter].
enum InputPhase { capture, target, bubble }

/// Result returned by an input handler.
enum InputDisposition { ignored, handled, stopPropagation }

typedef InputHandler = InputDisposition Function(
  InputEvent event,
  InputPhase phase,
);

/// Deterministic three-phase input dispatcher.
///
/// Capture handlers run from the application root toward the target, target
/// handlers run once, and bubble handlers run from the target back toward the
/// root. Returning [InputDisposition.stopPropagation] ends dispatch
/// immediately. Returning [InputDisposition.handled] records that the event was
/// consumed while still allowing later handlers to observe it.
final class InputRouter {
  InputRouter({
    Iterable<InputHandler> capture = const <InputHandler>[],
    Iterable<InputHandler> target = const <InputHandler>[],
    Iterable<InputHandler> bubble = const <InputHandler>[],
  })  : _capture = List<InputHandler>.of(capture),
        _target = List<InputHandler>.of(target),
        _bubble = List<InputHandler>.of(bubble);

  final List<InputHandler> _capture;
  final List<InputHandler> _target;
  final List<InputHandler> _bubble;

  List<InputHandler> get captureHandlers =>
      List<InputHandler>.unmodifiable(_capture);
  List<InputHandler> get targetHandlers =>
      List<InputHandler>.unmodifiable(_target);
  List<InputHandler> get bubbleHandlers =>
      List<InputHandler>.unmodifiable(_bubble);

  void add(InputPhase phase, InputHandler handler) {
    _handlersFor(phase).add(handler);
  }

  bool remove(InputPhase phase, InputHandler handler) {
    return _handlersFor(phase).remove(handler);
  }

  InputDisposition route(InputEvent event) {
    var handled = false;

    InputDisposition dispatch(
      Iterable<InputHandler> handlers,
      InputPhase phase,
    ) {
      for (final handler in handlers) {
        final disposition = handler(event, phase);
        if (disposition == InputDisposition.stopPropagation) {
          return disposition;
        }
        handled |= disposition == InputDisposition.handled;
      }
      return InputDisposition.ignored;
    }

    var result = dispatch(_capture, InputPhase.capture);
    if (result == InputDisposition.stopPropagation) return result;

    result = dispatch(_target, InputPhase.target);
    if (result == InputDisposition.stopPropagation) return result;

    result = dispatch(_bubble.reversed, InputPhase.bubble);
    if (result == InputDisposition.stopPropagation) return result;

    return handled ? InputDisposition.handled : InputDisposition.ignored;
  }

  List<InputHandler> _handlersFor(InputPhase phase) => switch (phase) {
        InputPhase.capture => _capture,
        InputPhase.target => _target,
        InputPhase.bubble => _bubble,
      };
}
