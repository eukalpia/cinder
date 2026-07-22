export 'src/backend/terminal.dart';
export 'src/backend/terminal_backend.dart';
// Platform-specific backends use conditional exports.
export 'src/backend/stdio_backend_export.dart';
export 'src/backend/socket_backend_export.dart';
export 'src/backend/web_backend_export.dart';
export 'src/buffer.dart';
export 'src/style.dart';
export 'src/shutdown.dart' show shutdownApp;
export 'src/components/progress_bar.dart';
export 'src/components/icon.dart';
export 'src/components/repaint_boundary.dart';
export 'src/components/scrollbar.dart';
export 'src/test/cinder_tester.dart';
export 'src/test/terminal_state.dart';
export 'src/test/matchers.dart';
export 'src/size.dart';
export 'src/rectangle.dart';
export 'src/test/cinder_test_binding.dart';
export 'src/binding/terminal_binding.dart';
export 'src/binding/run_app.dart' show runApp;
export 'src/binding/scheduler_binding.dart';
export 'src/binding/scheduler_phase.dart';
export 'src/components/basic.dart';
export 'src/components/builder.dart';
export 'src/components/focus.dart';
export 'src/components/focusable.dart';
export 'src/components/block_focus.dart';
export 'src/components/scroll_controller.dart';
export 'src/components/auto_scroll_controller.dart';
export 'src/components/single_child_scroll_view.dart';
export 'src/components/list_view.dart';
export 'src/components/text_field.dart';
export 'src/components/terminal_xterm.dart';
export 'cinder_test.dart';
export 'src/framework/framework.dart';
export 'src/framework/axis.dart';

export 'src/components/spacer.dart';
export 'src/components/divider.dart';
export 'src/process/pty_controller.dart';
export 'src/components/stack.dart';
export 'src/components/render_stack.dart' show Stack;
export 'src/components/clip.dart';
export 'src/components/performance_overlay.dart';
export 'src/components/controls.dart';
export 'src/components/application_widgets.dart';

// Application actions and shared interaction state.
export 'src/actions/actions.dart';
export 'src/actions/command_palette.dart';
export 'src/foundation/widget_state.dart';

// Data visualization and virtualized data views.
export 'src/data/charts.dart';
export 'src/data/data_table.dart';
export 'src/data/tree_view.dart';

// Navigation.
export 'src/navigation/navigator.dart';
export 'src/navigation/route.dart';
export 'src/navigation/route_settings.dart';
export 'src/navigation/pop_behavior.dart';
export 'src/navigation/navigator_observer.dart';
export 'src/navigation/overlay.dart';

export 'src/components/markdown_text.dart';
export 'src/components/rich_text.dart';
export 'src/framework/listenable.dart';
export 'src/framework/value_listenable.dart';
export 'src/components/value_listenable_builder.dart';
// LayoutBuilder is exported via framework.dart (it is a part file).

// Mouse and gesture support.
export 'src/components/mouse_region.dart';
export 'src/components/gesture_detector.dart';
export 'src/gestures/events.dart';
export 'src/gestures/hit_test.dart';
export 'src/gestures/recognizer.dart';
export 'src/gestures/tap.dart';
export 'src/gestures/long_press.dart';

// Utilities.
export 'src/utils/clipboard.dart';
export 'src/utils/log_server.dart';
export 'src/utils/logger.dart';
export 'src/utils/cinder_paths.dart';
export 'src/utils/escape_codes.dart';
export 'src/utils/terminal_text.dart';

// Lifecycle and structured concurrency.
export 'src/foundation/cancellation.dart';
export 'src/foundation/resource_scope.dart';

// Performance and debugging.
export 'src/foundation/performance.dart';
export 'src/foundation/cinder_error.dart';
export 'src/foundation/debug_options.dart';
export 'src/rendering/debug.dart';
export 'src/components/debug_overlay.dart';

// Semantics, plain output, and development diagnostics.
export 'src/semantics/semantics.dart';
export 'src/output/plain_output.dart';
export 'src/devtools/diagnostics.dart';

// Widgets.
export 'src/widgets/cinder_app.dart';

// Theme.
export 'src/theme/theme.dart';

// ASCII text.
export 'src/components/ascii_text.dart';
export 'src/components/ascii_font.dart' show AsciiFont, AsciiGlyph;

// Animation.
export 'src/animation/animations.dart';
export 'src/animation/animated_builder.dart';

// Modal barrier.
export 'src/components/modal_barrier.dart';

// Image support.
export 'src/components/image.dart';
export 'src/image/image_cleanup.dart' show ImageProtocol;
export 'src/image/terminal_capabilities.dart';

// Text selection.
export 'src/components/selection_area.dart';
export 'src/components/selection_scope.dart';
export 'src/components/selectable.dart';
