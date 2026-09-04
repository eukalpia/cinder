import 'package:cinder/cinder.dart';

import 'change_notifier_provider.dart';
import 'provider.dart';

/// Listens to a [Listenable], expose it to its descendants and rebuilds
/// dependents whenever the listener emits an event.
///
/// For usage information, see [ChangeNotifierProvider], a subclass of
/// [ListenableProvider] made for [ChangeNotifier].
///
/// You will generally want to use [ChangeNotifierProvider] instead.
/// But [ListenableProvider] is available in case you want to implement
/// [Listenable] yourself, or use [Animation].
class ListenableProvider<T extends Listenable?> extends InheritedProvider<T> {
  /// Creates a [Listenable] using [create] and subscribes to it.
  ///
  /// [dispose] can optionally passed to free resources
  /// when [ListenableProvider] is removed from the tree.
  ///
  /// [create] must not be `null`.
  ListenableProvider({
    super.key,
    required Create<T> super.create,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(startListening: _startListening);

  /// Provides an existing [Listenable].
  ListenableProvider.value({
    super.key,
    required super.value,
    super.updateShouldNotify,
    super.builder,
    super.child,
  }) : super.value(startListening: _startListening);

  static VoidCallback _startListening(
    InheritedContext<Listenable?> e,
    Listenable? value,
  ) {
    value?.addListener(e.markNeedsNotifyDependents);
    return () => value?.removeListener(e.markNeedsNotifyDependents);
  }
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider0<R extends Listenable?>
    extends InheritedProvider<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider0({
    super.key,
    super.create,
    required R Function(BuildContext, R? previous) super.update,
    super.dispose,
    super.updateShouldNotify,
    super.lazy,
    super.builder,
    super.child,
  }) : super(startListening: ListenableProvider._startListening);
}

/// {@template provider.listenableproxyprovider}
/// A variation of [ListenableProvider] that builds its value from
/// values obtained from other providers.
///
/// See the discussion on [ChangeNotifierProxyProvider] for a complete
/// explanation on how to use it.
///
/// [ChangeNotifierProxyProvider] extends [ListenableProxyProvider] to make it
/// work with [ChangeNotifier], but the behavior stays the same.
/// Most of the time you'll want to use [ChangeNotifierProxyProvider] instead.
/// But [ListenableProxyProvider] is exposed in case someone wants to use a
/// [Listenable] implementation other than [ChangeNotifier], such as
/// [Animation].
/// {@endtemplate}
class ListenableProxyProvider<T, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider({
    super.key,
    super.create,
    required ProxyProviderBuilder<T, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) =>
             update(context, Provider.of(context), previous),
       );
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider2<T, T2, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider2({
    super.key,
    super.create,
    required ProxyProviderBuilder2<T, T2, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of(context),
           Provider.of(context),
           previous,
         ),
       );
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider3<T, T2, T3, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider3({
    super.key,
    super.create,
    required ProxyProviderBuilder3<T, T2, T3, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           previous,
         ),
       );
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider4<T, T2, T3, T4, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider4({
    super.key,
    super.create,
    required ProxyProviderBuilder4<T, T2, T3, T4, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           previous,
         ),
       );
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider5<T, T2, T3, T4, T5, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider5({
    super.key,
    super.create,
    required ProxyProviderBuilder5<T, T2, T3, T4, T5, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           previous,
         ),
       );
}

/// {@macro provider.listenableproxyprovider}
class ListenableProxyProvider6<T, T2, T3, T4, T5, T6, R extends Listenable?>
    extends ListenableProxyProvider0<R> {
  /// Initializes [key] for subclasses.
  ListenableProxyProvider6({
    super.key,
    super.create,
    required ProxyProviderBuilder6<T, T2, T3, T4, T5, T6, R> update,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           Provider.of(context),
           previous,
         ),
       );
}
