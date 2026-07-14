import 'package:bloc/bloc.dart';
import 'package:cinder/cinder.dart';

import 'bloc_builder.dart';

/// Signature for selecting a derived value from a bloc state.
typedef BlocWidgetSelector<S, T> = T Function(S state);

/// Rebuilds only when the selected value changes.
class BlocSelector<B extends StateStreamableSource<S>, S, T>
    extends StatelessWidget {
  const BlocSelector({
    super.key,
    this.bloc,
    required this.selector,
    required this.builder,
  });

  final B? bloc;
  final BlocWidgetSelector<S, T> selector;
  final Widget Function(BuildContext context, T state) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<B, S>(
      bloc: bloc,
      buildWhen: (previous, current) {
        return selector(previous) != selector(current);
      },
      builder: (context, state) => builder(context, selector(state)),
    );
  }
}
