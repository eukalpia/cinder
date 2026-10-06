import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

/// Regression tests for slot propagation when keyed children are reordered
/// with *new* (non-identical) widget instances.
///
/// `Element.updateChild` only moved a child's render object when the new
/// widget was identical to the old one (e.g. a reused `const` widget). When
/// the widget could be updated in place (`Widget.canUpdate`), the element
/// was updated but its slot was not, so the render objects kept their old
/// order. The text of each row changed while its position did not.
/// `update_child_slot_test.dart` and `move_child_relayout_test.dart` only
/// cover `const` children, which take the identical-widget branch.
void main() {
  group('keyed reorder of non-const children', () {
    test('reversing keyed Text children reorders the Column', () async {
      await testCinder('reverse keyed Text', (tester) async {
        await tester.pumpWidget(const _ReversibleColumn());
        expect(tester.toSnapshot(), 'AAA·0\nBBB·1\nCCC·2');

        tester.findState<_ReversibleColumnState>().reverse();
        await tester.pump();

        expect(
          tester.toSnapshot(),
          'CCC·0\nBBB·1\nAAA·2',
          reason:
              'each keyed Text is rebuilt with a new widget and a new slot; '
              'its render object must move to the new position',
        );
      }, size: const Size(10, 3));
    });

    test('reordering keyed stateful children moves them and keeps their '
        'state', () async {
      await testCinder('reorder keyed stateful', (tester) async {
        _RowState._nextSerial = 0;
        await tester.pumpWidget(const _ReorderableStatefulColumn());
        expect(tester.toSnapshot(), 'A#0@0\nB#1@1\nC#2@2');

        tester.findState<_ReorderableStatefulColumnState>().rotate();
        await tester.pump();

        // Each row keeps the creation serial of its State (#n) and reports
        // its new index (@n), so the elements were reused, not recreated.
        expect(
          tester.toSnapshot(),
          'B#1@0\nC#2@1\nA#0@2',
          reason:
              'the slot must reach the Text render object below each keyed '
              'StatefulElement so the rows move',
        );
      }, size: const Size(10, 3));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _ReversibleColumn extends StatefulWidget {
  const _ReversibleColumn();

  @override
  State<_ReversibleColumn> createState() => _ReversibleColumnState();
}

class _ReversibleColumnState extends State<_ReversibleColumn> {
  List<String> _items = const ['AAA', 'BBB', 'CCC'];

  void reverse() {
    setState(() => _items = _items.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _items)
          Text('$item ${_items.indexOf(item)}', key: ValueKey(item)),
      ],
    );
  }
}

class _ReorderableStatefulColumn extends StatefulWidget {
  const _ReorderableStatefulColumn();

  @override
  State<_ReorderableStatefulColumn> createState() =>
      _ReorderableStatefulColumnState();
}

class _ReorderableStatefulColumnState
    extends State<_ReorderableStatefulColumn> {
  List<String> _labels = const ['A', 'B', 'C'];

  /// Moves the first label to the end.
  void rotate() {
    setState(() => _labels = [..._labels.skip(1), _labels.first]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _labels.length; i++)
          _Row(key: ValueKey(_labels[i]), label: _labels[i], index: i),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.label, required this.index});

  final String label;
  final int index;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  static int _nextSerial = 0;

  late final int _serial;

  @override
  void initState() {
    super.initState();
    _serial = _nextSerial++;
  }

  @override
  Widget build(BuildContext context) {
    return Text('${widget.label}#$_serial@${widget.index}');
  }
}
