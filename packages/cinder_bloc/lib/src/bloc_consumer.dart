import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';

import 'bloc_builder.dart';
import 'bloc_listener.dart';

/// Combines [BlocBuilder] and [BlocListener] for the same bloc.
class BlocConsumer<B extends StateStreamableSource<S>, S>
    extends StatelessWidget {
  const BlocConsumer({
    super.key,
    this.bloc,
    this.buildWhen,
    this.listenWhen,
    required this.listener,
    required this.builder,
  });

  final B? bloc;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocListenerCondition<S>? listenWhen;
  final BlocWidgetListener<S> listener;
  final BlocWidgetBuilder<S> builder;

  @override
  Widget build(BuildContext context) {
    return BlocListener<B, S>(
      bloc: bloc,
      listenWhen: listenWhen,
      listener: listener,
      child: BlocBuilder<B, S>(
        bloc: bloc,
        buildWhen: buildWhen,
        builder: builder,
      ),
    );
  }
}
