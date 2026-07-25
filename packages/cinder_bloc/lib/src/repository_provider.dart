import 'package:cinder/cinder.dart';
import 'package:cinder_nested/nested.dart';
import 'package:cinder_provider/provider.dart';

/// Provides a repository or service object to a Cinder subtree.
class RepositoryProvider<T> extends SingleChildStatelessWidget {
  RepositoryProvider({
    required T Function(BuildContext context) create,
    super.key,
    super.child,
    this.lazy = true,
    void Function(T value)? dispose,
  })  : _create = create,
        _value = null,
        _dispose = dispose;

  RepositoryProvider.value({
    required T value,
    super.key,
    super.child,
  })  : _value = value,
        _create = null,
        _dispose = null,
        lazy = true;

  final T Function(BuildContext context)? _create;
  final T? _value;
  final void Function(T value)? _dispose;
  final bool lazy;

  static T of<T>(BuildContext context, {bool listen = false}) {
    return Provider.of<T>(context, listen: listen);
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    assert(
      child != null,
      '$runtimeType used outside MultiRepositoryProvider must specify a child.',
    );

    final value = _value;
    if (value != null) {
      return Provider<T>.value(value: value, child: child);
    }

    final disposer = _dispose;
    return Provider<T>(
      create: _create!,
      dispose: disposer == null ? null : (_, value) => disposer(value),
      lazy: lazy,
      child: child,
    );
  }
}

/// Merges multiple repository providers into one widget tree.
class MultiRepositoryProvider extends MultiProvider {
  MultiRepositoryProvider({
    super.key,
    required super.providers,
    required super.child,
  });
}
