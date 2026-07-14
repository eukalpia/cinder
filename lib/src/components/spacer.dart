import '../framework/framework.dart';
import 'basic.dart';

class Spacer extends StatelessWidget {
  const Spacer({super.key, this.flex = 1});

  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: const SizedBox(),
    );
  }
}
