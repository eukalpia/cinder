part of 'framework.dart';

/// A widget that does not require mutable state.
abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});

  @override
  StatelessElement createElement() => StatelessElement(this);

  /// Describes the part of the user interface represented by this widget.
  @protected
  Widget build(BuildContext context);
}

/// Element for StatelessWidget
class StatelessElement extends BuildableElement {
  StatelessElement(StatelessWidget super.widget);

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    // Trigger a rebuild when the widget is updated to ensure
    // child components receive state updates from parent
    rebuild();
  }

  @override
  StatelessWidget get widget => super.widget as StatelessWidget;

  @override
  Widget build() => widget.build(this);
}
