import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class TestApp extends StatefulWidget {
  const TestApp({super.key});

  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  final controller1 = TextEditingController(text: 'field1');
  final controller2 = TextEditingController(text: 'field2');
  final focusNode1 = FocusNode(debugLabel: 'field1');
  final focusNode2 = FocusNode(debugLabel: 'field2');
  int focusedField = 0;

  @override
  void dispose() {
    controller1.dispose();
    controller2.dispose();
    focusNode1.dispose();
    focusNode2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Column(
        children: [
          TextField(
            controller: controller1,
            focusNode: focusNode1,
            autofocus: true,
            onFocusChange: (focused) {
              if (focused) setState(() => focusedField = 0);
            },
          ),
          TextField(
            controller: controller2,
            focusNode: focusNode2,
            onFocusChange: (focused) {
              if (focused) setState(() => focusedField = 1);
            },
          ),
        ],
      ),
    );
  }
}

void main() {
  group('TextField Focus Management', () {
    test('TextField exposes Flutter-style focus configuration', () {
      final node = FocusNode(debugLabel: 'field');
      final field = TextField(
        focusNode: node,
        autofocus: true,
        onFocusChange: (_) {},
      );

      expect(field.focusNode, same(node));
      expect(field.autofocus, isTrue);
      node.dispose();
    });

    test('TextField keeps onFocusChange callback', () {
      final field = TextField(
        onFocusChange: (_) {},
      );

      expect(field.onFocusChange, isNotNull);
    });

    test('TextEditingController manages text independently of focus', () {
      final controller = TextEditingController(text: 'initial');
      final firstNode = FocusNode();
      final secondNode = FocusNode();

      final first = TextField(
        controller: controller,
        focusNode: firstNode,
        autofocus: true,
      );
      final second = TextField(
        controller: controller,
        focusNode: secondNode,
      );

      expect(first.controller, same(controller));
      expect(second.controller, same(controller));

      controller.text = 'updated';
      expect(controller.text, 'updated');

      firstNode.dispose();
      secondNode.dispose();
      controller.dispose();
    });

    test('multiple TextFields retain distinct FocusNodes', () {
      final nodes = List.generate(3, (index) => FocusNode(debugLabel: '$index'));
      final fields = List.generate(
        3,
        (index) => TextField(
          focusNode: nodes[index],
          autofocus: index == 0,
        ),
      );

      for (var index = 0; index < fields.length; index++) {
        expect(fields[index].focusNode, same(nodes[index]));
      }
      expect(fields.first.autofocus, isTrue);
      expect(fields[1].autofocus, isFalse);

      for (final node in nodes) {
        node.dispose();
      }
    });
  });
}
