import 'package:cinder/cinder.dart';

void main() {
  runApp(const CenterInColumn());
}

class CenterInColumn extends StatelessWidget {
  const CenterInColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Center(
        child: Text('Hello, World!'),
      ),
      Center(
        child: Text('Hello, World!'),
      ),
    ]);
  }
}
