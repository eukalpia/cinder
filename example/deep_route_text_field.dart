import 'dart:math' as math;

import 'package:cinder/cinder.dart';

void main() {
  runApp(const Navigator(
    home: MyAppWithNavigation(depth: 0),
  ));
}

class NoNavigation extends StatefulWidget {
  const NoNavigation({super.key});

  @override
  State<NoNavigation> createState() => _NoNavigationState();
}

class _NoNavigationState extends State<NoNavigation> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) => event.logicalKey == LogicalKey.tab,
      child: Center(
        child: Container(
          width: 56,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            border: BoxBorder.all(color: Colors.gray),
          ),
          child: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class MyAppWithNavigation extends StatefulWidget {
  const MyAppWithNavigation({super.key, this.depth = 0});

  final int depth;

  @override
  State<MyAppWithNavigation> createState() => _MyAppWithNavigationState();
}

class _MyAppWithNavigationState extends State<MyAppWithNavigation> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.tab) {
          Navigator.of(context).push(
            PageRoute(
              builder: (context) =>
                  MyAppWithNavigation(depth: widget.depth + 1),
              settings: RouteSettings(name: 'depth_${widget.depth}'),
            ),
          );
          return true;
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 80.0;
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 28.0;
          final panelWidth = math.max(20.0, math.min(72.0, availableWidth - 4));
          final panelHeight = math.max(8.0, math.min(18.0, availableHeight - 4));

          if (widget.depth != 5 && widget.depth != 0) {
            return Center(
              child: Text(
                'Depth ${widget.depth} — press Tab to continue',
                style: const TextStyle(color: Colors.magenta),
              ),
            );
          }

          return Center(
            child: Container(
              width: panelWidth,
              height: panelHeight,
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: const Color.fromRGB(7, 9, 14),
                border: BoxBorder.all(color: Colors.gray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'DEEP ROUTE TEXT FIELD',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'DEPTH ${widget.depth}',
                        style: const TextStyle(color: Colors.magenta),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    'Type below. Tab pushes the next route.',
                    style: TextStyle(color: Colors.gray),
                  ),
                  const SizedBox(height: 1),
                  TextField(controller: controller, autofocus: true),
                  const Spacer(),
                  Text(
                    '${panelWidth.toInt()}×${panelHeight.toInt()} cells · responsive layout',
                    style: const TextStyle(color: Colors.gray),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
