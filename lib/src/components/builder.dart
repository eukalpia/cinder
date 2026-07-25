import '../framework/framework.dart';

class Builder extends StatelessWidget {
  /// Creates a widget that delegates its build to a callback.
  const Builder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
