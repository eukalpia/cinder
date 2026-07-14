import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';
import 'package:cinder_provider/provider.dart' as provider;

/// Flutter BLoC-compatible helpers on [BuildContext].
extension ReadContext on BuildContext {
  /// Read a bloc, cubit, repository, or service without subscribing.
  T read<T>() => provider.Provider.of<T>(this, listen: false);
}

extension WatchContext on BuildContext {
  /// Subscribe to a provided bloc, cubit, repository, or service.
  ///
  /// For [StateStreamableSource] values, [BlocProvider] marks dependents when
  /// the state stream emits.
  T watch<T>() => provider.Provider.of<T>(this);
}

extension SelectContext on BuildContext {
  /// Subscribe to only a selected portion of a provided object.
  R select<T, R>(R Function(T value) selector) {
    return provider.SelectContext(this).select<T, R>(selector);
  }

  /// Select a value directly from a bloc's current state.
  R selectState<B extends StateStreamableSource<S>, S, R>(
    R Function(S state) selector,
  ) {
    return provider.SelectContext(this).select<B, R>(
      (bloc) => selector(bloc.state),
    );
  }
}
