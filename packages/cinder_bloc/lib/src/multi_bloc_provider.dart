import 'package:cinder/cinder.dart';
import 'package:cinder_nested/nested.dart';
import 'package:cinder_provider/provider.dart';

/// Merges multiple [SingleChildWidget] providers into one widget tree.
class MultiBlocProvider extends MultiProvider {
  MultiBlocProvider({
    super.key,
    required List<SingleChildWidget> providers,
    required Widget child,
  }) : super(providers: providers, child: child);
}
