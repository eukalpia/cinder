import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('diagnostics capture widget, render and focus trees', () async {
    await testCinder('diagnostics snapshot', (tester) async {
      await tester.pumpWidget(
        const Focus(
          autofocus: true,
          child: Semantics(
            properties: SemanticsProperties(
              role: SemanticsRole.text,
              label: 'Ready',
            ),
            child: Text('Ready'),
          ),
        ),
      );
      final snapshot = CinderDiagnostics.capture();
      expect(snapshot.widgetTree, isNotNull);
      expect(snapshot.widgetTree!.format(), contains('Focus'));
      expect(snapshot.renderTrees.length, greaterThan(0));
      expect(snapshot.focusTree.format(), contains('primary=true'));
      expect(snapshot.semantics.toPlainText(), contains('Ready'));
    });
  });
}
