import 'package:cinder/cinder.dart';
import 'package:cinder/src/rendering/extent_index.dart';
import 'package:test/test.dart';

class _HistoryHost extends StatefulWidget {
  const _HistoryHost(
      {super.key, required this.controller, required this.initialIds});

  final AnchoredListController controller;
  final List<int> initialIds;

  @override
  State<_HistoryHost> createState() => _HistoryHostState();
}

class _HistoryHostState extends State<_HistoryHost> {
  late List<int> ids = List<int>.of(widget.initialIds);
  final Map<int, double> heights = <int, double>{};
  int buildCount = 0;

  void prepend(Iterable<int> values) {
    setState(() => ids = <int>[...values, ...ids]);
  }

  void setHeight(int id, double height) {
    setState(() => heights[id] = height);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 10,
      child: AnchoredListView<int>.builder(
        controller: widget.controller,
        itemIds: ids,
        estimatedItemExtent: 1,
        cacheExtent: 3,
        itemBuilder: (_, index, id) {
          buildCount++;
          return SizedBox(
            height: heights[id] ?? (id.isEven ? 1 : 2),
            child: Text('message $id'),
          );
        },
      ),
    );
  }
}

void main() {
  test(
    'ExtentIndex keeps stable-ID measurements across reorder and eviction',
    () {
      final index = ExtentIndex<String>(
        estimatedExtent: 2,
        maxCachedExtents: 10,
      );
      index.syncItems(<String>['a', 'b', 'c']);
      index.updateExtent('b', 7);

      expect(index.offsetOfId('c'), 9);
      index.syncItems(<String>['x', 'b', 'c']);
      expect(index.knownExtentForId('b'), 7);
      expect(index.offsetOfId('c'), 9);
    },
  );

  test(
    '100k variable-height history starts and jumps without eager building',
    () async {
      final controller = AnchoredListController();
      final key = GlobalKey<_HistoryHostState>();

      await testCinder('large anchored history', (tester) async {
        await tester.pumpWidget(
          _HistoryHost(
            key: key,
            controller: controller,
            initialIds: List<int>.generate(100000, (index) => index),
          ),
        );

        expect(key.currentState!.buildCount, lessThan(100));
        key.currentState!.buildCount = 0;
        expect(controller.jumpToItem(50000), isTrue);
        await tester.pump();

        expect(key.currentState!.buildCount, lessThan(100));
        expect(tester.terminalState, containsText('message 50000'));
      });
      controller.dispose();
    },
  );

  test('prepending old messages preserves the stable item anchor', () async {
    final controller = AnchoredListController();
    final key = GlobalKey<_HistoryHostState>();

    await testCinder('prepend anchor stability', (tester) async {
      await tester.pumpWidget(
        _HistoryHost(
          key: key,
          controller: controller,
          initialIds: List<int>.generate(100, (index) => index + 100),
        ),
      );
      controller.jumpToItem(150, localOffset: 0.5);
      await tester.pump();
      final before = controller.anchor;
      expect(before?.itemId, 150);

      key.currentState!.prepend(List<int>.generate(100, (index) => index));
      await tester.pump();
      final after = controller.anchor;

      expect(after?.itemId, before?.itemId);
      expect(after?.localOffset, closeTo(before!.localOffset, 0.001));
    });
    controller.dispose();
  });

  test(
    'late media relayout corrects scroll without moving the anchor',
    () async {
      final controller = AnchoredListController();
      final key = GlobalKey<_HistoryHostState>();

      await testCinder('media extent correction', (tester) async {
        await tester.pumpWidget(
          _HistoryHost(
            key: key,
            controller: controller,
            initialIds: List<int>.generate(40, (index) => index),
          ),
        );
        controller.jumpToItem(6, localOffset: 0.25);
        await tester.pump();
        final before = controller.anchor;

        key.currentState!.setHeight(4, 6);
        await tester.pump();
        final after = controller.anchor;

        expect(after?.itemId, before?.itemId);
        expect(after?.localOffset, closeTo(before!.localOffset, 0.001));
      });
      controller.dispose();
    },
  );

  test(
    'controller saves and restores an independent position per chat',
    () async {
      final controller = AnchoredListController();
      final key = GlobalKey<_HistoryHostState>();

      await testCinder('per chat position', (tester) async {
        await tester.pumpWidget(
          _HistoryHost(
            key: key,
            controller: controller,
            initialIds: List<int>.generate(100, (index) => index),
          ),
        );
        controller.jumpToItem(20);
        await tester.pump();
        expect(controller.savePosition('chat-a'), isTrue);

        controller.jumpToItem(70);
        await tester.pump();
        expect(controller.anchor?.itemId, 70);

        expect(controller.restorePosition('chat-a'), isTrue);
        await tester.pump();
        expect(controller.anchor?.itemId, 20);
      });
      controller.dispose();
    },
  );
  test(
    'legacy lazy ListView retains an O(log n) variable-extent start index',
    () async {
      final controller = ScrollController();
      var builds = 0;

      await testCinder('lazy ListView start index', (tester) async {
        await tester.pumpWidget(
          SizedBox(
            width: 40,
            height: 10,
            child: ListView.builder(
              controller: controller,
              lazy: true,
              itemCount: 100000,
              itemBuilder: (_, index) {
                builds++;
                return SizedBox(
                  height: index.isEven ? 1 : 2,
                  child: Text('legacy $index'),
                );
              },
            ),
          ),
        );
        expect(builds, lessThan(100));

        builds = 0;
        controller.jumpTo(50000);
        await tester.pump();
        expect(builds, lessThan(100));
        expect(tester.terminalState, containsText('legacy 33333'));
      });
      controller.dispose();
    },
  );
}
