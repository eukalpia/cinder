import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// Interactive, procedural terminal city used by the Cinder web showcase.
///
/// The scene is rendered entirely by Cinder: every road, tower, window, spark,
/// HUD panel, hover target, and animation frame is produced from terminal cells.
void main() {
  runApp(const CinderApp(child: InteractiveCinderCity()));
}

class InteractiveCinderCity extends StatefulWidget {
  const InteractiveCinderCity({super.key});

  @override
  State<InteractiveCinderCity> createState() => _InteractiveCinderCityState();
}

class _InteractiveCinderCityState extends State<InteractiveCinderCity> {
  Timer? _timer;
  int _tick = 0;
  int _selected = 0;
  int? _hovered;
  bool _paused = false;
  bool _showHud = true;
  bool _motion = true;
  final Set<int> _boosted = <int>{0};
  final List<String> _events = <String>[
    'CORE ONLINE',
    'WEB BACKEND LINKED',
    'DAMAGE TRACKER ARMED',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _paused || !_motion) return;
      setState(() => _tick = (_tick + 1) % 1000000);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _record(String event) {
    _events.insert(0, event);
    if (_events.length > 6) _events.removeLast();
  }

  void _select(int index, String source) {
    if (_selected == index) return;
    setState(() {
      _selected = index;
      _record('$source → SECTOR ${index.toString().padLeft(2, '0')}');
    });
  }

  void _toggleBoost(int index) {
    setState(() {
      if (_boosted.remove(index)) {
        _record('SECTOR ${index.toString().padLeft(2, '0')} NORMALIZED');
      } else {
        _boosted.add(index);
        _record('SECTOR ${index.toString().padLeft(2, '0')} BOOSTED');
      }
    });
  }

  void _cycle(int delta, int count) {
    final next = (_selected + delta + count) % count;
    _select(next, 'KEYBOARD');
  }

  bool _handleKey(KeyEvent event, int buildingCount) {
    final key = event.logicalKey;
    if (key == LogicalKey.arrowLeft || key == LogicalKey.keyH) {
      _cycle(-1, buildingCount);
      return true;
    }
    if (key == LogicalKey.arrowRight || key == LogicalKey.keyL) {
      _cycle(1, buildingCount);
      return true;
    }
    if (key == LogicalKey.arrowUp || key == LogicalKey.keyK) {
      _cycle(-3, buildingCount);
      return true;
    }
    if (key == LogicalKey.arrowDown || key == LogicalKey.keyJ) {
      _cycle(3, buildingCount);
      return true;
    }
    if (key == LogicalKey.tab) {
      _cycle(1, buildingCount);
      return true;
    }
    if (key == LogicalKey.enter) {
      _toggleBoost(_selected);
      return true;
    }
    if (key == LogicalKey.space) {
      setState(() {
        _paused = !_paused;
        _record(_paused ? 'SIMULATION PAUSED' : 'SIMULATION RESUMED');
      });
      return true;
    }
    if (key == LogicalKey.keyM) {
      setState(() {
        _motion = !_motion;
        _record(_motion ? 'MOTION ENABLED' : 'MOTION FROZEN');
      });
      return true;
    }
    if (key == LogicalKey.keyI) {
      setState(() => _showHud = !_showHud);
      return true;
    }
    if (key == LogicalKey.keyR) {
      setState(() {
        _tick = 0;
        _selected = 0;
        _hovered = null;
        _paused = false;
        _motion = true;
        _boosted
          ..clear()
          ..add(0);
        _events
          ..clear()
          ..addAll(<String>[
            'CORE ONLINE',
            'WEB BACKEND LINKED',
            'DAMAGE TRACKER ARMED',
          ]);
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(48, constraints.maxWidth.floor());
        final height = math.max(22, constraints.maxHeight.floor());
        final compact = width < 92 || height < 31;
        final scene = _CityScene.compose(
          width: width,
          height: height,
          tick: _tick,
          selected: _selected,
          hovered: _hovered,
          boosted: _boosted,
          compact: compact,
        );

        return Focus(
          autofocus: true,
          onKeyEvent: (event) => _handleKey(event, scene.buildings.length),
          child: Container(
            color: const Color.fromRGB(3, 4, 8),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: RepaintBoundary(
                    child: RichText(
                      text: scene.span,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      maxLines: height,
                    ),
                  ),
                ),
                ...scene.buildings.asMap().entries.map((entry) {
                  final index = entry.key;
                  final building = entry.value;
                  return Positioned(
                    left: building.hitLeft.toDouble(),
                    top: building.hitTop.toDouble(),
                    width: building.hitWidth.toDouble(),
                    height: building.hitHeight.toDouble(),
                    child: MouseRegion(
                      onEnter: (_) {
                        if (_hovered == index) return;
                        setState(() => _hovered = index);
                      },
                      onExit: (_) {
                        if (_hovered != index) return;
                        setState(() => _hovered = null);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _select(index, 'POINTER');
                          _toggleBoost(index);
                        },
                        onDoubleTap: () {
                          setState(() {
                            _selected = index;
                            _boosted
                              ..clear()
                              ..add(index);
                            _record('ISOLATED ${building.name}');
                          });
                        },
                        child: Container(),
                      ),
                    ),
                  );
                }),
                if (_showHud && !compact) ..._desktopHud(scene),
                if (_showHud && compact) ..._compactHud(scene),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _desktopHud(_CityScene scene) {
    final selected = scene.buildings[_selected % scene.buildings.length];
    return <Widget>[
      Positioned(
        left: 2,
        top: 1,
        width: 21,
        height: 7,
        child: _HudPanel(
          title: 'STATE',
          tone: _Tone.orange,
          lines: <String>[
            'SYS  ${_paused ? 'HOLD' : 'LIVE'}',
            'NET  ONLINE',
            'BUF  ${scene.dirtyCells.toString().padLeft(4, '0')}',
          ],
        ),
      ),
      Positioned(
        right: 2,
        top: 1,
        width: 21,
        height: 7,
        child: _HudPanel(
          title: 'DIFF',
          tone: _Tone.purple,
          lines: <String>[
            'LOW  ${scene.diffLow.toString().padLeft(3, '0')}',
            'HIGH ${scene.diffHigh.toString().padLeft(3, '0')}',
            'MODE MINIMAL',
          ],
        ),
      ),
      Positioned(
        left: 2,
        bottom: 2,
        width: 28,
        height: 8,
        child: _HudPanel(
          title: 'EVENTS',
          tone: _Tone.orange,
          lines: _events
              .take(4)
              .map((event) => '› $event')
              .toList(growable: false),
        ),
      ),
      Positioned(
        right: 2,
        bottom: 2,
        width: 24,
        height: 8,
        child: _HudPanel(
          title: 'FRAME',
          tone: _Tone.orange,
          lines: <String>[
            '${scene.frameMs.toStringAsFixed(1)}ms  ${_paused ? 'PAUSED' : 'RUN'}',
            'FPS ${(1000 / scene.frameMs).round()}',
            'TICK ${_tick.toString().padLeft(6, '0')}',
            '▁▃▂▅▄▇▅▆▃▅',
          ],
        ),
      ),
      Positioned(
        right: 28,
        bottom: 2,
        width: 32,
        height: 8,
        child: _HudPanel(
          title: selected.name.toUpperCase(),
          tone: _boosted.contains(_selected) ? _Tone.pink : _Tone.cyan,
          lines: <String>[
            'SECTOR ${_selected.toString().padLeft(2, '0')}',
            'LOAD ${selected.load(_tick).toString().padLeft(3, '0')}%',
            'CELLS ${selected.cellCount}',
            _boosted.contains(_selected) ? 'STATUS BOOSTED' : 'STATUS STABLE',
          ],
        ),
      ),
      Positioned(
        left: 31,
        bottom: 1,
        right: 61,
        height: 2,
        child: Text(
          ' [ARROWS/HJKL] SELECT  [ENTER/CLICK] BOOST  [SPACE] PAUSE  [M] MOTION  [I] HUD  [R] RESET ',
          style: const TextStyle(color: Colors.gray),
        ),
      ),
    ];
  }

  List<Widget> _compactHud(_CityScene scene) {
    final selected = scene.buildings[_selected % scene.buildings.length];
    return <Widget>[
      Positioned(
        left: 1,
        top: 0,
        right: 1,
        height: 2,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              ' CINDER CITY / ${selected.name.toUpperCase()} ',
              style: const TextStyle(
                color: Colors.magenta,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${scene.frameMs.toStringAsFixed(1)}ms ',
              style: const TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
      Positioned(
        left: 1,
        bottom: 0,
        right: 1,
        height: 2,
        child: Text(
          ' ←→ SELECT  ENTER BOOST  SPACE PAUSE  I HUD ',
          style: const TextStyle(color: Colors.gray),
        ),
      ),
    ];
  }
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.title,
    required this.lines,
    required this.tone,
  });

  final String title;
  final List<String> lines;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: const Color.fromRGB(4, 5, 10),
        border: BoxBorder.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          ...lines.map(
            (line) => Text(
              line,
              style: TextStyle(
                color: line.contains('ONLINE') || line.contains('LIVE')
                    ? Colors.green
                    : Colors.brightWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CityScene {
  const _CityScene({
    required this.span,
    required this.buildings,
    required this.dirtyCells,
    required this.diffLow,
    required this.diffHigh,
    required this.frameMs,
  });

  final TextSpan span;
  final List<_Building> buildings;
  final int dirtyCells;
  final int diffLow;
  final int diffHigh;
  final double frameMs;

  static _CityScene compose({
    required int width,
    required int height,
    required int tick,
    required int selected,
    required int? hovered,
    required Set<int> boosted,
    required bool compact,
  }) {
    final buffer = _SceneBuffer(width, height);
    final seed = width * 37 + height * 19;
    _drawSky(buffer, tick, seed);

    final centerX = width ~/ 2;
    final centerY = compact ? height ~/ 2 + 1 : height ~/ 2;
    final scale = compact ? 0.72 : math.min(1.0, width / 132.0);
    final buildings = _layoutBuildings(centerX, centerY, scale, compact);

    _drawNetwork(buffer, centerX, centerY, tick, compact);
    for (var index = 0; index < buildings.length; index++) {
      final building = buildings[index];
      final highlighted = index == selected || index == hovered;
      _drawBuilding(
        buffer,
        building,
        tick: tick,
        highlighted: highlighted,
        boosted: boosted.contains(index),
      );
    }

    _drawCore(buffer, centerX, centerY, tick, compact);
    _drawParticles(buffer, centerX, centerY, tick, compact);

    final dirtyCells = 88 + ((tick * 17 + selected * 29) % 210);
    final diffLow = 8 + ((tick * 3) % 24);
    final diffHigh = 48 + ((tick * 7 + boosted.length * 13) % 72);
    final frameMs = 15.4 + ((tick % 9) * 0.17);

    return _CityScene(
      span: buffer.toTextSpan(),
      buildings: buildings,
      dirtyCells: dirtyCells,
      diffLow: diffLow,
      diffHigh: diffHigh,
      frameMs: frameMs,
    );
  }
}

class _Building {
  const _Building({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.depth,
    required this.tone,
    required this.seed,
  });

  final String name;
  final int x;
  final int y;
  final int width;
  final int height;
  final int depth;
  final _Tone tone;
  final int seed;

  int get hitLeft => x - depth;
  int get hitTop => y;
  int get hitWidth => width + depth * 2 + 1;
  int get hitHeight => height + depth + 3;
  int get cellCount => math.max(12, width * height * 2);

  int load(int tick) => 28 + ((tick * 5 + seed * 17) % 69);
}

enum _Tone { dim, purple, orange, pink, white, green, red, cyan }

class _SceneBuffer {
  _SceneBuffer(this.width, this.height)
      : _glyphs = List<List<String>>.generate(
          height,
          (_) => List<String>.filled(width, ' '),
        ),
        _tones = List<List<_Tone>>.generate(
          height,
          (_) => List<_Tone>.filled(width, _Tone.dim),
        ),
        _priority = List<List<int>>.generate(
          height,
          (_) => List<int>.filled(width, 0),
        );

  final int width;
  final int height;
  final List<List<String>> _glyphs;
  final List<List<_Tone>> _tones;
  final List<List<int>> _priority;

  void put(int x, int y, String glyph, _Tone tone, [int priority = 1]) {
    if (x < 0 || y < 0 || x >= width || y >= height || glyph.isEmpty) return;
    if (priority < _priority[y][x]) return;
    _glyphs[y][x] = glyph;
    _tones[y][x] = tone;
    _priority[y][x] = priority;
  }

  void text(int x, int y, String value, _Tone tone, [int priority = 1]) {
    for (var index = 0; index < value.length; index++) {
      put(x + index, y, value[index], tone, priority);
    }
  }

  void line(int x1, int y1, int x2, int y2, _Tone tone, int tick) {
    final dx = (x2 - x1).abs();
    final dy = (y2 - y1).abs();
    final sx = x1 < x2 ? 1 : -1;
    final sy = y1 < y2 ? 1 : -1;
    var error = dx - dy;
    var x = x1;
    var y = y1;
    var step = 0;
    while (true) {
      final pulse = (step + tick) % 13 == 0;
      put(x, y, pulse ? '◆' : (dx >= dy ? '─' : '│'),
          pulse ? _Tone.orange : tone, 2);
      if (x == x2 && y == y2) break;
      final e2 = error * 2;
      if (e2 > -dy) {
        error -= dy;
        x += sx;
      }
      if (e2 < dx) {
        error += dx;
        y += sy;
      }
      step++;
    }
  }

  TextSpan toTextSpan() {
    final spans = <InlineSpan>[];
    for (var y = 0; y < height; y++) {
      var currentTone = _tones[y][0];
      final run = StringBuffer();
      for (var x = 0; x < width; x++) {
        final tone = _tones[y][x];
        if (tone != currentTone && run.isNotEmpty) {
          spans.add(
              TextSpan(text: run.toString(), style: _styleFor(currentTone)));
          run.clear();
          currentTone = tone;
        }
        run.write(_glyphs[y][x]);
      }
      if (run.isNotEmpty) {
        spans
            .add(TextSpan(text: run.toString(), style: _styleFor(currentTone)));
      }
      if (y != height - 1) spans.add(const TextSpan(text: '\n'));
    }
    return TextSpan(children: spans);
  }
}

List<_Building> _layoutBuildings(
  int centerX,
  int centerY,
  double scale,
  bool compact,
) {
  int sx(double value) => (value * scale).round();
  int sy(double value) => (value * (compact ? 0.68 : scale)).round();
  final specs = <_Building>[
    _Building(
        name: 'Cinder Core',
        x: centerX - sx(12),
        y: centerY - sy(4),
        width: sx(20),
        height: sy(5),
        depth: sx(4),
        tone: _Tone.purple,
        seed: 1),
    _Building(
        name: 'Widget Tower',
        x: centerX - sx(47),
        y: centerY - sy(15),
        width: sx(12),
        height: sy(12),
        depth: sx(3),
        tone: _Tone.purple,
        seed: 2),
    _Building(
        name: 'Element Stack',
        x: centerX - sx(28),
        y: centerY - sy(18),
        width: sx(10),
        height: sy(15),
        depth: sx(3),
        tone: _Tone.cyan,
        seed: 3),
    _Building(
        name: 'Render Spire',
        x: centerX - sx(8),
        y: centerY - sy(20),
        width: sx(11),
        height: sy(17),
        depth: sx(3),
        tone: _Tone.purple,
        seed: 4),
    _Building(
        name: 'Buffer Array',
        x: centerX + sx(17),
        y: centerY - sy(18),
        width: sx(12),
        height: sy(15),
        depth: sx(3),
        tone: _Tone.orange,
        seed: 5),
    _Building(
        name: 'Diff Tower',
        x: centerX + sx(39),
        y: centerY - sy(15),
        width: sx(11),
        height: sy(12),
        depth: sx(3),
        tone: _Tone.purple,
        seed: 6),
    _Building(
        name: 'Input Hub',
        x: centerX - sx(56),
        y: centerY + sy(4),
        width: sx(12),
        height: sy(8),
        depth: sx(3),
        tone: _Tone.orange,
        seed: 7),
    _Building(
        name: 'Focus Grid',
        x: centerX - sx(35),
        y: centerY + sy(8),
        width: sx(12),
        height: sy(9),
        depth: sx(3),
        tone: _Tone.purple,
        seed: 8),
    _Building(
        name: 'Scheduler',
        x: centerX + sx(22),
        y: centerY + sy(8),
        width: sx(12),
        height: sy(9),
        depth: sx(3),
        tone: _Tone.orange,
        seed: 9),
    _Building(
        name: 'Web Backend',
        x: centerX + sx(45),
        y: centerY + sy(4),
        width: sx(12),
        height: sy(8),
        depth: sx(3),
        tone: _Tone.purple,
        seed: 10),
    _Building(
        name: 'Image Node',
        x: centerX - sx(18),
        y: centerY + sy(14),
        width: sx(10),
        height: sy(7),
        depth: sx(3),
        tone: _Tone.pink,
        seed: 11),
    _Building(
        name: 'Terminal Link',
        x: centerX + sx(4),
        y: centerY + sy(15),
        width: sx(10),
        height: sy(7),
        depth: sx(3),
        tone: _Tone.cyan,
        seed: 12),
  ];
  return compact ? specs.take(7).toList(growable: false) : specs;
}

void _drawSky(_SceneBuffer buffer, int tick, int seed) {
  for (var y = 0; y < buffer.height; y++) {
    for (var x = 0; x < buffer.width; x++) {
      final hash = (x * 73 + y * 151 + seed) % 997;
      if (hash % 47 == 0) {
        final bright = (hash + tick) % 17 == 0;
        buffer.put(
            x, y, bright ? '✦' : '·', bright ? _Tone.pink : _Tone.dim, 1);
      } else if (hash % 79 == 0) {
        buffer.put(x, y, '·', _Tone.purple, 1);
      }
    }
  }
}

void _drawNetwork(
  _SceneBuffer buffer,
  int centerX,
  int centerY,
  int tick,
  bool compact,
) {
  final radiusX = compact ? 35 : math.min(58, buffer.width ~/ 2 - 4);
  final radiusY = compact ? 10 : math.min(17, buffer.height ~/ 2 - 3);
  final hubs = <(int, int)>[
    (centerX - radiusX, centerY - radiusY ~/ 2),
    (centerX - radiusX ~/ 2, centerY - radiusY),
    (centerX + radiusX ~/ 2, centerY - radiusY),
    (centerX + radiusX, centerY - radiusY ~/ 2),
    (centerX + radiusX, centerY + radiusY ~/ 2),
    (centerX + radiusX ~/ 2, centerY + radiusY),
    (centerX - radiusX ~/ 2, centerY + radiusY),
    (centerX - radiusX, centerY + radiusY ~/ 2),
  ];
  for (var index = 0; index < hubs.length; index++) {
    final hub = hubs[index];
    buffer.line(
        centerX, centerY + 2, hub.$1, hub.$2, _Tone.purple, tick + index * 3);
    if (index > 0) {
      final previous = hubs[index - 1];
      buffer.line(previous.$1, previous.$2, hub.$1, hub.$2, _Tone.orange,
          tick + index * 5);
    }
  }
  final last = hubs.last;
  final first = hubs.first;
  buffer.line(last.$1, last.$2, first.$1, first.$2, _Tone.orange, tick);
}

void _drawBuilding(
  _SceneBuffer buffer,
  _Building building, {
  required int tick,
  required bool highlighted,
  required bool boosted,
}) {
  final x = building.x;
  final y = building.y;
  final width = math.max(6, building.width);
  final height = math.max(4, building.height);
  final depth = math.max(2, building.depth);
  final roofTone = highlighted ? _Tone.pink : building.tone;
  final wallTone = boosted ? _Tone.orange : building.tone;

  buffer.text(x, y, '╱${'─' * width}╲', roofTone, 5);
  for (var layer = 1; layer <= depth; layer++) {
    buffer.text(x - layer, y + layer, '╱', roofTone, 5);
    buffer.text(x - layer + 1, y + layer, '░' * width, roofTone, 4);
    buffer.text(x + width, y + layer, '╲', roofTone, 5);
  }
  buffer.text(x - depth, y + depth + 1, '╰${'─' * width}╯', roofTone, 5);

  final bodyTop = y + depth + 2;
  for (var row = 0; row < height; row++) {
    buffer.put(x - depth, bodyTop + row, '│', wallTone, 5);
    buffer.put(x + width + 1, bodyTop + row, '│', wallTone, 5);
    for (var column = 0; column < width; column++) {
      final window = (row + column + building.seed + tick ~/ 4) % 5 == 0;
      final glyph = window
          ? (boosted ? '◆' : '·')
          : ((column + row) % 3 == 0 ? '│' : ' ');
      final tone = window ? (boosted ? _Tone.orange : _Tone.purple) : _Tone.dim;
      buffer.put(x - depth + 1 + column, bodyTop + row, glyph, tone, 4);
    }
  }
  buffer.text(x - depth, bodyTop + height, '╰${'─' * (width + depth + 1)}╯',
      wallTone, 5);

  if (highlighted && width >= 8) {
    final label = building.name.toUpperCase();
    final clipped = label.length > width ? label.substring(0, width) : label;
    buffer.text(
        x + (width - clipped.length) ~/ 2, y + depth, clipped, _Tone.white, 7);
  }
}

void _drawCore(
  _SceneBuffer buffer,
  int centerX,
  int centerY,
  int tick,
  bool compact,
) {
  final width = compact ? 16 : 22;
  final x = centerX - width ~/ 2;
  final y = centerY - 3;
  buffer.text(x, y, '╱${'═' * width}╲', _Tone.pink, 9);
  buffer.text(x - 1, y + 1, '╱${'░' * width}╲', _Tone.purple, 9);
  buffer.text(x - 2, y + 2, '╱${'─' * width}╲', _Tone.purple, 9);
  buffer.text(x - 2, y + 3, '│${' ' * width}│', _Tone.purple, 9);
  buffer.text(
      x - 2, y + 4, '│${_center('>_  CINDER', width)}│', _Tone.white, 10);
  buffer.text(x - 2, y + 5, '╰${'═' * width}╯', _Tone.pink, 9);

  final flameHeight = compact ? 8 : 13;
  for (var row = 0; row < flameHeight; row++) {
    final phase = (tick + row * 2) % 5;
    final ratio = 1 - row / flameHeight;
    final half =
        math.max(0, (ratio * (compact ? 5 : 8)).round() + (phase == 0 ? 1 : 0));
    final flameY = y - 1 - row;
    for (var dx = -half; dx <= half; dx++) {
      final edge = dx.abs() == half;
      final inner = dx.abs() < half ~/ 2;
      final glyph = edge ? '░' : (inner ? '█' : '▓');
      final tone = inner
          ? _Tone.orange
          : row < flameHeight ~/ 3
              ? _Tone.pink
              : _Tone.purple;
      buffer.put(
          centerX + dx + ((row + tick) % 3) - 1, flameY, glyph, tone, 12);
    }
  }
}

void _drawParticles(
  _SceneBuffer buffer,
  int centerX,
  int centerY,
  int tick,
  bool compact,
) {
  final count = compact ? 16 : 34;
  for (var index = 0; index < count; index++) {
    final orbit = 8 + (index % (compact ? 13 : 25));
    final phase = (tick + index * 11) % 97;
    final x = centerX + (((phase * 17 + index * 23) % (orbit * 2 + 1)) - orbit);
    final y = centerY - 5 - ((tick * 2 + index * 7) % math.max(8, centerY - 3));
    final glyph = index % 5 == 0 ? '✦' : (index % 3 == 0 ? '◆' : '·');
    buffer.put(x, y, glyph, index.isEven ? _Tone.pink : _Tone.orange, 11);
  }
}

String _center(String value, int width) {
  if (value.length >= width) return value.substring(0, width);
  final left = (width - value.length) ~/ 2;
  return '${' ' * left}$value${' ' * (width - value.length - left)}';
}

TextStyle _styleFor(_Tone tone) => TextStyle(color: _colorFor(tone));

Color _colorFor(_Tone tone) {
  switch (tone) {
    case _Tone.dim:
      return const Color.fromRGB(63, 56, 82);
    case _Tone.purple:
      return const Color.fromRGB(176, 91, 255);
    case _Tone.orange:
      return const Color.fromRGB(255, 132, 34);
    case _Tone.pink:
      return const Color.fromRGB(255, 67, 171);
    case _Tone.white:
      return const Color.fromRGB(240, 234, 250);
    case _Tone.green:
      return const Color.fromRGB(114, 213, 114);
    case _Tone.red:
      return const Color.fromRGB(255, 92, 109);
    case _Tone.cyan:
      return const Color.fromRGB(100, 200, 226);
  }
}
