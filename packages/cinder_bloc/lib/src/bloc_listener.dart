import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';

import 'bloc_provider.dart';

/// Signature for reacting to a bloc state.
typedef BlocWidgetListener<S> = void Function(BuildContext context, S state);

/// Signature for filtering listener notifications.
typedef BlocListenerCondition<S> = bool Function(S previous, S current);

/// Invokes [listener] for matching state changes without rebuilding [child].
class BlocListener<B extends StateStreamableSource<S>, S>
    extends StatefulWidget {
  const BlocListener({
    super.key,
    this.bloc,
    this.listenWhen,
    required this.listener,
    required this.child,
  });

  final B? bloc;
  final BlocListenerCondition<S>? listenWhen;
  final BlocWidgetListener<S> listener;
  final Widget child;

  @override
  State<BlocListener<B, S>> createState() => _BlocListenerState<B, S>();
}

class _BlocListenerState<B extends StateStreamableSource<S>, S>
    extends State<BlocListener<B, S>> {
  late B _bloc;
  late S _previousState;
  StreamSubscription<S>? _subscription;

  B _resolveBloc() => widget.bloc ?? BlocProvider.of<B>(context);

  void _subscribe() {
    _previousState = _bloc.state;
    _subscription = _bloc.stream.listen((state) {
      final shouldListen =
          widget.listenWhen?.call(_previousState, state) ?? true;
      _previousState = state;
      if (shouldListen && mounted) {
        widget.listener(context, state);
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
  void didUpdateWidget(BlocListener<B, S> oldWidget) {
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
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
