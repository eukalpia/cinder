import 'package:cinder/cinder.dart';

void main() {
  // Super performant
  // runApp(const NoNavigation());
  // return;

  // Super slow
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
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.tab) {
          return true;
        }
        return false;
      },
      child: TextField(controller: controller, focused: true),
    );
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
          Navigator.of(context).push(PageRoute(
              builder: (context) =>
                  MyAppWithNavigation(depth: widget.depth + 1),
              settings: RouteSettings(name: 'depth_${widget.depth}')));
          return true;
        }
        return false;
      },
      child: widget.depth == 5 || widget.depth == 0
          ? Container(
              decoration: BoxDecoration(
                border: BoxBorder.all(color: Colors.gray),
              ),
              width: 100,
              height: 100,
              child: TextField(controller: controller, focused: true),
            )
          : Text('Depth: ${widget.depth}'),
    );
  }
}
