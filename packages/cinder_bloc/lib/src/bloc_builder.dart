import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';

import 'bloc_provider.dart';

/// Signature for deciding whether a state change should rebuild a widget.
typedef BlocBuilderCondition<S> = bool Function(S previous, S current);

/// Signature for building a widget from a bloc state.
typedef BlocWidgetBuilder<S> = Widget Function(BuildContext context, S state);

/// Rebuilds when the provided [Bloc] or [Cubit] emits a matching state.
class BlocBuilder<B extends StateStreamableSource<S>, S>
    extends StatefulWidget {
  const BlocBuilder({
    super.key,
    this.bloc,
    this.buildWhen,
    required this.builder,
  });

  final B? bloc;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocWidgetBuilder<S> builder;

  @override
  State<BlocBuilder<B, S>> createState() => _BlocBuilderState<B, S>();
}

class _BlocBuilderState<B extends StateStreamableSource<S>, S>
    extends State<BlocBuilder<B, S>> {
  late B _bloc;
  late S _state;
  StreamSubscription<S>? _subscription;

  B _resolveBloc() => widget.bloc ?? BlocProvider.of<B>(context);

  void _subscribe() {
    _state = _bloc.state;
    _subscription = _bloc.stream.listen((state) {
      final shouldBuild = widget.buildWhen?.call(_state, state) ?? true;
      if (shouldBuild && mounted) {
        setState(() => _state = state);
      } else {
        _state = state;
      }
    });
  }

  void _replaceBloc(B nextBloc) {
    if (identical(nextBloc, _bloc)) return;
    _subscription?.cancel();
    _bloc = nextBloc;
    _subscribe();
  }

  @override
  void initState() {
    super.initState();
    _bloc = _resolveBloc();
    _subscribe();
  }

  @override
  void didUpdateWidget(BlocBuilder<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _replaceBloc(_resolveBloc());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.bloc == null) {
      _replaceBloc(_resolveBloc());
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
