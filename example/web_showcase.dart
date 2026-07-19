import 'dart:async';

import 'package:cinder/cinder.dart';

/// Animated isometric terminal scene used by the Cinder documentation homepage.
void main() {
  runApp(const CinderApp(child: WebShowcase()));
}

class WebShowcase extends StatefulWidget {
  const WebShowcase({super.key});

  @override
  State<WebShowcase> createState() => _WebShowcaseState();
}

class _WebShowcaseState extends State<WebShowcase> {
  Timer? _timer;
  int _frame = 0;
  bool _showPipeline = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _flames.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scene = '$_cityTop${_flames[_frame]}$_cityBottom';

    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space) {
          setState(() => _showPipeline = !_showPipeline);
          return true;
        }
        return false;
      },
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(border: BoxBorder.all(color: Colors.magenta)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ' CINDER RENDER PIPELINE ',
                  style: TextStyle(
                    color: Colors.magenta,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _showPipeline ? 'STATE → FRAME → DIFF ' : 'SCENE MODE ',
                  style: TextStyle(color: Colors.yellow),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Expanded(
              child: Center(
                child: Text(
                  scene,
                  style: TextStyle(
                    color: Colors.magenta,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _showPipeline
                      ? ' WIDGET  →  ELEMENT  →  RENDER OBJECT  →  BUFFER  →  DIFF '
                      : ' SPACE: show pipeline ',
                  style: TextStyle(color: Colors.gray),
                ),
                Text(
                  'FRAME ${(_frame + 1).toString().padLeft(2, '0')}  ',
                  style: TextStyle(color: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

const _cityTop = r'''
        ┌────┐           ┌──────┐              ┌────┐
     ┌──┤░░░░├──┐     ┌──┤░░░░░░├──┐        ┌──┤░░░░├─┐
   ┌─┤░░│░░░░│░░├─┐ ┌─┤░░│░░░░░░│░░├─┐   ┌──┤░░│░░░░│░├─┐
   │░│░░│░░░░│░░│░│ │░│░░│░░░░░░│░░│░│   │░░│░░│░░░░│░│░│
   └─┴──┴─┬──┴──┴─┘ └─┴──┴──┬───┴──┴─┘   └──┴──┴─┬──┴─┴─┘
          │    ┌──────────────┐                    │
     ─────┴────┤  CELL GRID   ├───────────────┬────┴─────
               └──────┬───────┘               │
''';

const _flames = [
  r'''
                      ░
                     ▒▓▒
                    ▓███▓
                   ▒█████▒
                  ░▓█████▓░
                    ▓███▓
                     ▒▓▒
''',
  r'''
                     ▒░▒
                    ▓███▓
                   ▒█████▒
                  ▓███████▓
                   ▓█████▓
                    ▒███▒
                     ░▓░
''',
  r'''
                      ▓
                    ▒███▒
                   ▓█████▓
                  ▒███████▒
                   ▒█████▒
                    ▓███▓
                     ▒▓▒
''',
  r'''
                     ░▓░
                    ▓███▓
                  ░▓█████▓░
                  ▓███████▓
                   ▓█████▓
                    ▒███▒
                      ▓
''',
];

const _cityBottom = r'''
               ┌──────┴───────┐               │
       ┌───────┤  FRAME DIFF  ├───────┐       │
    ┌──┴──┐    └──────┬───────┘    ┌──┴──┐ ┌──┴──┐
   /░░░░░/│       ┌───┴───┐        /░░░░/│ /░░░░/│
  /_____/░│       │ WEB   │       /_____/░│/_____/░│
  │░░░░░│░│───────│BACKEND│───────│░░░░░│░│░░░░░│░│
  │░░░░░│/        └───┬───┘       │░░░░░│/│░░░░░│/
  └─────┘             └───────────└─────┘ └─────┘
''';
