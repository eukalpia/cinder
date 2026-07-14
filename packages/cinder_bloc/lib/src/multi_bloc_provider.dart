import 'package:cinder/cinder.dart';
import 'package:cinder_nested/nested.dart';
import 'package:cinder_provider/provider.dart';

/// Merges multiple bloc providers into one widget tree.
class MultiBlocProvider extends MultiProvider {
  MultiBlocProvider({
    super.key,
    required super.providers,
    required super.child,
  });
}
