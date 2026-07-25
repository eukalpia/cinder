import 'package:cinder/src/framework/framework.dart';
import 'package:cinder/src/framework/value_listenable.dart';

typedef ValueWidgetBuilder<T> = Widget Function(
    BuildContext context, T value, Widget? child);

class ValueListenableBuilder<T> extends StatefulWidget {
  const ValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  final ValueListenable<T> valueListenable;

  final ValueWidgetBuilder<T> builder;

  final Widget? child;

  @override
  State<StatefulWidget> createState() => _ValueListenableBuilderState<T>();
}

class _ValueListenableBuilderState<T> extends State<ValueListenableBuilder<T>> {
  late T value;

  @override
  void initState() {
    super.initState();
    value = widget.valueListenable.value;
    widget.valueListenable.addListener(_valueChanged);
  }

  @override
  void didUpdateWidget(ValueListenableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_valueChanged);
      value = widget.valueListenable.value;
      widget.valueListenable.addListener(_valueChanged);
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_valueChanged);
    super.dispose();
  }

  void _valueChanged() {
    setState(() {
      value = widget.valueListenable.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, value, widget.child);
  }
}
