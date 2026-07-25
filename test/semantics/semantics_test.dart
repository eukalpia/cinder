import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('SemanticsSnapshot exports plain text and JSON', () async {
    await testCinder('semantics snapshot', (tester) async {
      await tester.pumpWidget(
        const Semantics(
          properties: SemanticsProperties(
            role: SemanticsRole.group,
            label: 'Account',
          ),
          child: Semantics(
            properties: SemanticsProperties(
              role: SemanticsRole.checkbox,
              label: 'Notifications',
              checked: true,
            ),
            child: Text('Notifications'),
          ),
        ),
      );
      final snapshot = SemanticsSnapshot.capture();
      expect(snapshot.toPlainText(), contains('Account'));
      expect(snapshot.toPlainText(), contains('checked'));
      expect(snapshot.toJsonString(), contains('checkbox'));
    });
  });
}
