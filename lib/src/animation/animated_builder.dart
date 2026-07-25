import 'package:cinder/src/framework/framework.dart';
import 'package:cinder/src/framework/listenable.dart';

/// A widget that rebuilds when the given [Listenable] changes value.
///
/// [AnimatedWidget] is most commonly used with [Animation] objects, which are
/// [Listenable]s, but it can be used with any [Listenable], including
/// [ChangeNotifier] and [ValueNotifier].
///
/// This is an abstract class, you should create your own subclass that overrides
/// [build] to return the widget tree you want to build.
///
/// Example:
/// ```dart
/// class SpinningContainer extends AnimatedWidget {
///   const SpinningContainer({
///     super.key,
///     required AnimationController controller,
///   }) : super(listenable: controller);
///
///   @override
///   Widget build(BuildContext context) {
///     final controller = listenable as AnimationController;
///     return Transform.rotate(
///       angle: controller.value * 2.0 * math.pi,
///       child: Container(...),
///     );
///   }
/// }
/// ```
abstract class AnimatedWidget extends StatefulWidget {
  /// Creates a widget that rebuilds when [listenable] changes value.
  const AnimatedWidget({
    super.key,
    required this.listenable,
  });

  /// The [Listenable] to which this widget is listening.
  ///
  /// Commonly an [Animation] or a [ChangeNotifier].
  final Listenable listenable;

  /// Override this method to build the widget tree.
  ///
  /// This method is called every time [listenable] changes value.
  Widget build(BuildContext context);

  @override
  State<AnimatedWidget> createState() => _AnimatedWidgetState();
}

class _AnimatedWidgetState extends State<AnimatedWidget> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(AnimatedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listenable != oldWidget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    setState(() {
      // The listenable changed, rebuild.
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.build(context);
  }
}

/// Signature for the builder callback used by [AnimatedBuilder].
typedef AnimatedWidgetBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A general-purpose widget for building animations.
///
/// [AnimatedBuilder] is useful for simple animations where you need to rebuild
/// a widget whenever an animation changes. It listens to the [animation]
/// and rebuilds the subtree whenever the animation's value changes.
///
/// For more complex animations, consider using [AnimatedWidget] (if available)
/// or creating a custom [StatefulWidget] with a [State] that uses a
/// [TickerProviderStateMixin].
///
/// The [child] parameter is optional. If provided, it will be passed to the
/// [builder] callback. This is an optimization: if part of the widget subtree
/// does not depend on the animation, you can pass it as [child] to avoid
/// rebuilding that part on every animation frame.
///
/// ## Example
///
/// ```dart
/// AnimatedBuilder(
///   animation: _controller,
///   builder: (BuildContext context, Widget? child) {
///     return Transform.rotate(
///       angle: _controller.value * 2.0 * math.pi,
///       child: child,
///     );
///   },
///   child: Container(
///     width: 200.0,
///     height: 200.0,
///     child: Text('Whee!'),
///   ),
/// )
/// ```
///
/// In this example, the [Text] widget would be passed to the [builder] as
/// [child], and would not be rebuilt on every animation frame.
class AnimatedBuilder extends StatefulWidget {
  /// Creates an animated builder.
  ///
  /// The [animation] and [builder] arguments are required.
  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  /// The [Listenable] to which this widget is listening.
  ///
  /// Commonly an [Animation] or a [ChangeNotifier].
  final Listenable animation;

  /// Called every time the animation changes value.
  ///
  /// The child given to the builder should typically be part of the returned
  /// widget tree, and should typically be constructed once and passed
  /// to the [AnimatedBuilder] as a child rather than constructed in the
  /// builder callback.
  final AnimatedWidgetBuilder builder;

  /// The child widget to pass to the [builder].
  ///
  /// If a builder callback's return value contains a subtree that does not
  /// depend on the animation, it's more efficient to build that subtree once
  /// instead of rebuilding it on every animation tick.
  ///
  /// If the pre-built subtree is passed as the [child] parameter, the
  /// [AnimatedBuilder] will pass it back to the [builder] function so that it
  /// can be incorporated into the build.
  ///
  /// Using this pre-built child is entirely optional, but can improve
  /// performance significantly in some cases and is therefore a good practice.
  final Widget? child;

  @override
  State<AnimatedBuilder> createState() => _AnimatedBuilderState();
}

class _AnimatedBuilderState extends State<AnimatedBuilder> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(AnimatedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation.removeListener(_handleChange);
      widget.animation.addListener(_handleChange);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    setState(() {
      // The animation changed, rebuild.
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}

/// A widget that rebuilds when a [Listenable] notifies its listeners.
///
/// [ListenableBuilder] is similar to [AnimatedBuilder], but is designed to
/// work with any [Listenable], not just animations. It's useful when you need
/// to rebuild a widget in response to notifications from a [ChangeNotifier]
/// or similar object.
///
/// ## Example
///
/// ```dart
/// ListenableBuilder(
///   listenable: myChangeNotifier,
///   builder: (BuildContext context, Widget? child) {
///     return Text('Current value: ${myChangeNotifier.value}');
///   },
/// )
/// ```
class ListenableBuilder extends StatefulWidget {
  /// Creates a listenable builder.
  ///
  /// The [listenable] and [builder] arguments are required.
  const ListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  /// The [Listenable] to which this widget is listening.
  final Listenable listenable;

  /// Called every time the listenable notifies its listeners.
  final AnimatedWidgetBuilder builder;

  /// The child widget to pass to the [builder].
  final Widget? child;

  @override
  State<ListenableBuilder> createState() => _ListenableBuilderState();
}

class _ListenableBuilderState extends State<ListenableBuilder> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(ListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listenable != oldWidget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    setState(() {
      // The listenable changed, rebuild.
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}
