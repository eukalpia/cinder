import 'package:cinder/cinder.dart';

void main() {
  runApp(const DialogTextFieldTest());
}

class DialogTextFieldTest extends StatelessWidget {
  const DialogTextFieldTest({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      home: const HomePage(),
      popBehavior: const PopBehavior(
        escapeEnabled: true,
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: [
          const Text('Home Page'),
          const SizedBox(height: 2),
          const Text('Press D to show dialog with TextField'),
          const SizedBox(height: 1),
          KeyboardListener(
            autofocus: true,
            onKeyEvent: (key) {
              if (key == LogicalKey.keyD) {
                Navigator.of(context).showDialog(
                  builder: (context) => const TextFieldDialog(),
                  width: 40,
                  height: 10,
                  barrierDismissible: true,
                );
                return true;
              }
              return false;
            },
            child: const Text('(waiting for D key...)'),
          ),
        ],
      ),
    );
  }
}

class TextFieldDialog extends StatefulWidget {
  const TextFieldDialog({super.key});

  @override
  State<TextFieldDialog> createState() => _TextFieldDialogState();
}

class _TextFieldDialogState extends State<TextFieldDialog> {
  String _value = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        children: [
          const Text('Dialog with TextField'),
          const SizedBox(height: 1),
          TextField(
            onChanged: (v) => setState(() => _value = v),
          ),
          const SizedBox(height: 1),
          Text('Value: $_value'),
          const Text('Press ESC to close'),
        ],
      ),
    );
  }
}
