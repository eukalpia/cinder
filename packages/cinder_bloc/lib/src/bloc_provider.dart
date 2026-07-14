import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';
import 'package:cinder_nested/nested.dart';
import 'package:cinder_provider/provider.dart';

/// Provides a [Bloc] or [Cubit] to a Cinder widget subtree.
class BlocProvider<T extends StateStreamableSource<Object?>>
    extends SingleChildStatelessWidget {
  const BlocProvider({
    required T Function(BuildContext context) create,
    super.key,
    this.child,
    this.lazy = true,
  })  : _create = create,
        _value = null,
        super(child: child);

  const BlocProvider.value({
    required T value,
    super.key,
    this.child,
  })  : _value = value,
        _create = null,
        lazy = true,
        super(child: child);

  final Widget? child;
  final bool lazy;
  final T Function(BuildContext context)? _create;
  final T? _value;

  static T of<T extends StateStreamableSource<Object?>>(
    BuildContext context, {
    bool listen = false,
  }) {
    return Provider.of<T>(context, listen: listen);
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    assert(
      child != null,
      '$runtimeType used outside MultiBlocProvider must specify a child.',
    );

    final value = _value;
    if (value != null) {
      return InheritedProvider<T>.value(
        value: value,
        startListening: _startListening,
        lazy: lazy,
        child: child,
      );
    }

    return InheritedProvider<T>(
      create: _create,
      dispose: (_, bloc) {
        bloc.close();
      },
      startListening: _startListening,
      lazy: lazy,
      child: child,
    );
  }

  static VoidCallback _startListening(
    InheritedContext<StateStreamable<dynamic>?> context,
    StateStreamable<dynamic> value,
  ) {
    final subscription = value.stream.listen(
      (_) => context.markNeedsNotifyDependents(),
    );
    return subscription.cancel;
  }
}
