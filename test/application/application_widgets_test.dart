import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('virtualized application widgets', () {
    test('VirtualListView builds a bounded visible window', () async {
      var builds = 0;
      await testCinder('virtual list visible window', (tester) async {
        await tester.pumpWidget(
          VirtualListView.builder(
            itemCount: 10000,
            itemExtent: 1,
            cacheExtent: 2,
            itemBuilder: (context, index) {
              builds++;
              return Text('row $index');
            },
          ),
        );

        expect(tester.terminalState, containsText('row 0'));
        expect(builds, lessThan(100));
      }, size: const Size(30, 8));
    });

    test('SplitView responds to keyboard resizing', () async {
      final controller = SplitViewController(ratio: 0.5);
      await testCinder('split view keyboard resize', (tester) async {
        await tester.pumpWidget(
          SplitView(
            controller: controller,
            autofocus: true,
            first: const Text('left'),
            second: const Text('right'),
          ),
        );
        await tester.sendArrowRight();

        expect(controller.ratio, greaterThan(0.5));
        expect(tester.terminalState, containsText('left'));
        expect(tester.terminalState, containsText('right'));
      }, size: const Size(40, 8));
      controller.dispose();
    });

    test(
      'TreeView expands and moves selection without eager mutation',
      () async {
        final controller = TreeViewController<String>(selectedId: 'root');
        await testCinder('tree keyboard navigation', (tester) async {
          await tester.pumpWidget(
            TreeView<String>(
              controller: controller,
              autofocus: true,
              nodes: const [
                TreeNode<String>(
                  id: 'root',
                  label: 'root\x1b[2J',
                  children: [TreeNode<String>(id: 'child', label: 'child')],
                ),
              ],
            ),
          );
          expect(tester.terminalState, containsText('root␛[2J'));
          expect(tester.terminalState.containsText('child'), isFalse);

          await tester.sendArrowRight();
          expect(tester.terminalState, containsText('child'));

          await tester.sendArrowDown();
          expect(controller.selectedId, 'child');
        }, size: const Size(40, 8));
        controller.dispose();
      },
    );

    test('DiffView parses hunks and dispatches approval', () async {
      const source = '''diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,2 +1,2 @@
-old
+new
 same''';
      final parsed = ParsedDiff.parse(source);
      expect(parsed.hunks, hasLength(1));
      expect(
        parsed.lines.any((line) => line.type == DiffLineType.addition),
        isTrue,
      );

      final controller = DiffViewController()..selectedLine = 3;
      DiffHunk? accepted;
      await testCinder('diff hunk approval', (tester) async {
        await tester.pumpWidget(
          DiffView(
            diff: source,
            controller: controller,
            autofocus: true,
            onAcceptHunk: (hunk) => accepted = hunk,
          ),
        );
        await tester.sendKey(LogicalKey.keyA);
        expect(accepted, isNotNull);
        expect(tester.terminalState, containsText('new'));
      }, size: const Size(60, 12));
      controller.dispose();
    });

    test('CommandPalette executes the selected command', () async {
      var executed = '';
      await testCinder('command palette execution', (tester) async {
        await tester.pumpWidget(
          CommandPalette(
            commands: [
              CommandItem(
                id: 'open',
                label: 'Open file',
                action: () => executed = 'open',
              ),
              CommandItem(
                id: 'save',
                label: 'Save file',
                action: () => executed = 'save',
              ),
            ],
          ),
        );
        await tester.sendArrowDown();
        await tester.sendEnter();
        expect(executed, 'save');
      }, size: const Size(80, 24));
    });
  });

  group('navigation and application surfaces', () {
    test('Tabs switch pages with arrow keys', () async {
      final controller = TabsController(selectedId: 'one');
      await testCinder('tabs keyboard switch', (tester) async {
        await tester.pumpWidget(
          Tabs(
            controller: controller,
            autofocus: true,
            tabs: const [
              TabItem(id: 'one', label: 'One', child: Text('first page')),
              TabItem(id: 'two', label: 'Two', child: Text('second page')),
            ],
          ),
        );
        expect(tester.terminalState, containsText('first page'));
        await tester.sendArrowRight();
        expect(controller.selectedId, 'two');
        expect(tester.terminalState, containsText('second page'));
      }, size: const Size(50, 10));
      controller.dispose();
    });

    test('Toast and NotificationCenter sanitize untrusted strings', () async {
      final toast = ToastController()
        ..show(
          const ToastMessage(
            id: 'one',
            title: 'alert\x1b[2J',
            message: 'message\x1b]52;c;bad\x07',
          ),
        );
      final notifications = NotificationCenterController([
        const NotificationItem(
          id: 'n',
          title: 'server\x1b[H',
          message: 'payload\x1b[31m',
        ),
      ]);

      await testCinder('safe application notices', (tester) async {
        await tester.pumpWidget(
          Column(
            children: [
              Toast(controller: toast),
              Expanded(child: NotificationCenter(controller: notifications)),
            ],
          ),
        );
        final text = tester.terminalState.getText();
        expect(text.contains('\x1b'), isFalse);
        expect(text, contains('alert␛[2J'));
        expect(text, contains('server␛[H'));
      }, size: const Size(70, 18));
      toast.dispose();
      notifications.dispose();
    });
  });

  group('data and developer widgets', () {
    test('VirtualDataGrid renders sanitized rows', () async {
      await testCinder('data grid safety', (tester) async {
        await tester.pumpWidget(
          VirtualDataGrid<String>(
            columns: [
              DataColumn<String>(
                id: 'value',
                label: 'Value',
                valueBuilder: (row) => row,
              ),
            ],
            rows: const ['safe', 'bad\x1b[2J'],
          ),
        );
        expect(tester.terminalState, containsText('bad␛[2J'));
        expect(tester.terminalState.getText().contains('\x1b'), isFalse);
      }, size: const Size(40, 10));
    });

    test(
      'ChatViewController coalesces deltas and ChatView renders safely',
      () async {
        final controller = ChatViewController(
          streamBatchInterval: Duration.zero,
          messages: const [
            ChatMessage(
              id: 'assistant',
              role: ChatRole.assistant,
              content: 'Hello ',
              streaming: true,
            ),
          ],
        );
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.appendDelta('assistant', 'world\x1b[2J');
        await Future<void>.delayed(Duration.zero);
        controller.flushPendingDeltas();
        expect(notifications, greaterThanOrEqualTo(1));
        expect(controller.messages.single.content, contains('world'));

        await testCinder('safe streaming chat', (tester) async {
          await tester.pumpWidget(ChatView(controller: controller));
          expect(tester.terminalState, containsText('world␛[2J'));
          expect(tester.terminalState.getText().contains('\x1b'), isFalse);
        }, size: const Size(70, 18));
        controller.dispose();
      },
    );

    test(
      'ToolCallCard and ApprovalDialog preserve terminal trust boundary',
      () async {
        var approved = false;
        await testCinder('agent surfaces safety', (tester) async {
          await tester.pumpWidget(
            Column(
              children: [
                const ToolCallCard(
                  toolName: 'shell\x1b[2J',
                  status: ToolCallStatus.succeeded,
                  output: 'output\x1b]0;title\x07',
                  initiallyExpanded: true,
                ),
                ApprovalDialog(
                  title: 'Approve',
                  command: 'rm -rf build\x1b[H',
                  onApprove: () => approved = true,
                  onDeny: () {},
                ),
              ],
            ),
          );
          expect(tester.terminalState.getText().contains('\x1b'), isFalse);
          await tester.sendEnter();
          expect(approved, isTrue);
        }, size: const Size(80, 24));
      },
    );
  });

  group('forms and controls', () {
    test('Form validates and updates a checkbox field', () async {
      final form = FormController();
      await testCinder('form validation', (tester) async {
        await tester.pumpWidget(
          Form(
            controller: form,
            child: FormField<bool>(
              id: 'accepted',
              initialValue: false,
              validators: [
                (value) => value == true ? null : 'Acceptance required',
              ],
              builder: (context, field) => Checkbox(
                autofocus: true,
                value: field.value ?? false,
                label: 'Accept terms',
                onChanged: (value) => field.value = value,
              ),
            ),
          ),
        );

        expect(form.fieldCount, 1);
        expect(form.validate(), isFalse);
        await tester.sendKey(LogicalKey.space);
        expect(form.validate(), isTrue);
        expect(form.value<bool>('accepted'), isTrue);
      }, size: const Size(50, 8));
      form.dispose();
    });

    test('Autocomplete selects a keyboard suggestion', () async {
      String? selected;
      await testCinder('autocomplete keyboard selection', (tester) async {
        await tester.pumpWidget(
          Autocomplete<String>(
            autofocus: true,
            options: const ['alpha', 'beta'],
            onSelected: (value) => selected = value,
          ),
        );
        await tester.enterText('be');
        await tester.sendEnter();
        expect(selected, 'beta');
      }, size: const Size(50, 10));
    });

    test('KeyRecorder captures a chord', () async {
      KeyChord? chord;
      await testCinder('key recorder', (tester) async {
        await tester.pumpWidget(
          KeyRecorder(
            autofocus: true,
            value: null,
            onChanged: (value) => chord = value,
          ),
        );
        await tester.sendEnter();
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyS,
            modifiers: ModifierKeys(ctrl: true, shift: true),
          ),
        );
        expect(chord?.label, 'Ctrl+Shift+S');
      }, size: const Size(40, 6));
    });
  });
}
