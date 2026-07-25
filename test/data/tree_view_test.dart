import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('TreeView expands nodes and navigates visible children', () async {
    TreeNode<String>? selected;
    await testCinder('tree view', (tester) async {
      await tester.pumpWidget(
        SizedBox(
          width: 32,
          height: 8,
          child: TreeView<String>(
            autofocus: true,
            nodes: <TreeNode<String>>[
              TreeNode<String>(
                id: 'root',
                label: 'Root',
                value: 'root',
                children: <TreeNode<String>>[
                  TreeNode<String>(id: 'child', label: 'Child', value: 'child'),
                ],
              ),
            ],
            onSelectionChanged: (node) => selected = node,
          ),
        ),
      );
      expect(tester.terminalState, containsText('Root'));
      await tester.sendKey(LogicalKey.arrowRight);
      await tester.pump();
      expect(tester.terminalState, containsText('Child'));
      await tester.sendKey(LogicalKey.arrowDown);
      expect(selected?.id, 'child');
    });
  });
}
