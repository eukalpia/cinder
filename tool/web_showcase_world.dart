import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// Coherent isometric Cinder city used by the web showcase.
///
/// The browser only hosts the terminal. The scene, animation, electricity,
/// pointer response, keyboard input, and responsive composition are rendered
/// by Cinder itself.
void main() {
  runApp(const CinderApp(child: WebShowcase()));
}

class WebShowcase extends StatefulWidget {
  const WebShowcase({super.key});

  @override
  State<WebShowcase> createState() => _WebShowcaseState();
}

class _WebShowcaseState extends State<WebShowcase> {
  Timer? _ticker;
  int _tick = 0;
  int _surgeUntil = 0;
  int _phase = 0;
  double _energy = 1;
  bool _paused = false;
  bool _hovered = false;

  bool get _surging => _tick < _surgeUntil;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted || _paused) return;
      setState(() => _tick++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _surge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = _extent(
                constraints.maxWidth,
                fallback: 150,
                maximum: 260,
              );
              final height = _extent(
                constraints.maxHeight,
                fallback: 52,
                maximum: 110,
              );
              final world = _IsometricCityPainter(
                width: width,
                height: height,
                tick: _tick + _phase,
                energy: _energy,
                surging: _surging,
                hovered: _hovered,
              ).paint();

              return Container(
                color: _Palette.background,
                child: RichText(
                  text: world.toTextSpan(),
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _handleKey(dynamic event) {
    final key = event.logicalKey;

    if (key == LogicalKey.space || key == LogicalKey.keyP) {
      setState(() => _paused = !_paused);
    } else if (key == LogicalKey.enter || key == LogicalKey.keyE) {
      _surge();
    } else if (key == LogicalKey.arrowUp) {
      setState(() => _energy = math.min(1.7, _energy + 0.1));
    } else if (key == LogicalKey.arrowDown) {
      setState(() => _energy = math.max(0.55, _energy - 0.1));
    } else if (key == LogicalKey.arrowLeft) {
      setState(() => _phase -= 4);
    } else if (key == LogicalKey.arrowRight) {
      setState(() => _phase += 4);
    } else if (key == LogicalKey.keyR) {
      setState(() {
        _tick = 0;
        _surgeUntil = 0;
        _phase = 0;
        _energy = 1;
        _paused = false;
      });
    } else {
      return false;
    }

    return true;
  }

  void _surge() {
    setState(() {
      _surgeUntil = _tick + 34;
      _energy = math.min(1.7, _energy + 0.08);
    });
  }

  int _extent(
    double value, {
    required int fallback,
    required int maximum,
  }) {
    if (!value.isFinite || value <= 0) return fallback;
    return value.floor().clamp(1, maximum).toInt();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class _IsometricCityPainter {
  _IsometricCityPainter({
    required this.width,
    required this.height,
    required this.tick,
    required this.energy,
    required this.surging,
    required this.hovered,
  }) : canvas = _WorldCanvas(width, height);

  final int width;
  final int height;
  final int tick;
  final double energy;
  final bool surging;
  final bool hovered;
  final _WorldCanvas canvas;

  late final int _tileX = width < 86 ? 3 : width < 132 ? 4 : 5;
  late final int _tileY = width < 86 ? 1 : 2;
  late final int _originX = width ~/ 2;
  late final int _originY = math.max(10, (height * 0.48).round()).toInt();

  final List<_Point> _roofNodes = <_Point>[];
  final List<List<_Point>> _powerLines = <List<_Point>>[];
  final List<List<_Point>> _roadLanes = <List<_Point>>[];

  _WorldCanvas paint() {
    if (width < 42 || height < 18) {
      _drawCompactCore();
      return canvas;
    }

    _drawBackdrop();
    _drawHud();
    _drawGroundGrid();
    _drawRoads();
    _drawBuildings();
    final core = _drawCorePlatform();
    _drawPowerNetwork(core);
    _drawElectricArcs();
    _drawFlame(core);
    _drawTraffic();
    _drawParticles(core);
    _drawDrone();

    return canvas;
  }

  void _drawCompactCore() {
    final cx = width ~/ 2;
    final base = height - 2;
    final top = math.max(1, height ~/ 5).toInt();

    for (var y = base - 5; y >= top; y--) {
      final sway = (math.sin(y * 0.8 + tick * 0.3) * 2).round();
      final radius = 1 + (base - y) % 3;
      for (var x = cx + sway - radius; x <= cx + sway + radius; x++) {
        final distance = (x - cx - sway).abs();
        canvas.set(
          x,
          y,
          distance == 0 ? '#' : distance == 1 ? '*' : '·',
          distance == 0 ? _Tone.white : distance == 1 ? _Tone.glow : _Tone.pink,
        );
      }
    }

    canvas.write(cx - 9, base - 3, '╭────────────────╮', _Tone.violet);
    canvas.write(cx - 9, base - 2, '│     CINDER     │', _Tone.orange);
    canvas.write(cx - 9, base - 1, '╰────────────────╯', _Tone.violet);
  }

  void _drawBackdrop() {
    final drift = tick ~/ 9;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hash = _noise(x, y, drift);
        if (hash % 277 == 0) {
          canvas.set(x, y, hash.isEven ? '·' : '.', _Tone.star);
        } else if (hash % 701 == 0) {
          canvas.set(x, y, tick.isEven ? '+' : '×', _Tone.pink);
        }
      }
    }

    final horizon = math.max(7, _originY - height ~/ 4).toInt();
    for (var x = 3; x < width - 3; x += 9) {
      final towerHeight = 2 + _noise(x, horizon, 19) % 7;
      canvas.vLine(x, horizon - towerHeight, horizon, '│', _Tone.depth);
      canvas.set(x, horizon - towerHeight - 1, '^', _Tone.depth);
      if ((x + tick ~/ 6) % 4 == 0) {
        canvas.set(x, horizon - towerHeight - 1, '·', _Tone.pink);
      }
    }
  }

  void _drawHud() {
    if (width < 92 || height < 32) return;

    _panel(2, 2, 13, 5, 'STATE', <String>['CORE', 'LIVE']);
    _panel(width - 15, 2, 13, 5, 'DIFF', <String>['CLEAN', 'LIVE']);
    _panel(2, height - 7, 16, 5, 'EVENTS', <String>['PULSE', 'ARC']);
    _panel(width - 18, height - 7, 16, 5, 'FRAME', <String>['ACTIVE', 'SYNC']);
  }

  void _panel(
    int x,
    int y,
    int panelWidth,
    int panelHeight,
    String title,
    List<String> rows,
  ) {
    canvas.set(x, y, '╭', _Tone.violetDim);
    canvas.hLine(x + 1, x + panelWidth - 2, y, '─', _Tone.violetDim);
    canvas.set(x + panelWidth - 1, y, '╮', _Tone.violetDim);
    canvas.vLine(x, y + 1, y + panelHeight - 2, '│', _Tone.violetDim);
    canvas.vLine(
      x + panelWidth - 1,
      y + 1,
      y + panelHeight - 2,
      '│',
      _Tone.violetDim,
    );
    canvas.set(x, y + panelHeight - 1, '╰', _Tone.violetDim);
    canvas.hLine(
      x + 1,
      x + panelWidth - 2,
      y + panelHeight - 1,
      '─',
      _Tone.violetDim,
    );
    canvas.set(x + panelWidth - 1, y + panelHeight - 1, '╯', _Tone.violetDim);
    canvas.write(x + 2, y + 1, title, _Tone.orange);
    for (var index = 0; index < rows.length && index < panelHeight - 2; index++) {
      canvas.write(x + 2, y + 2 + index, rows[index], _Tone.violet);
    }
  }

  void _drawGroundGrid() {
    final back = _iso(-7, -7, 0);
    final left = _iso(-7, 7, 0);
    final front = _iso(7, 7, 0);
    final right = _iso(7, -7, 0);

    _stroke(_polyline(<_Point>[back, right, front, left, back]), _Tone.depth);

    for (var lane = -6; lane <= 6; lane += 2) {
      _stroke(
        _polyline(<_Point>[_iso(lane, -7, 0), _iso(lane, 7, 0)]),
        _Tone.depth,
        sparse: true,
        phase: lane,
      );
      _stroke(
        _polyline(<_Point>[_iso(-7, lane, 0), _iso(7, lane, 0)]),
        _Tone.depth,
        sparse: true,
        phase: -lane,
      );
    }
  }

  void _drawRoads() {
    final loops = <List<_GridPoint>>[
      <_GridPoint>[
        const _GridPoint(-6, -4),
        const _GridPoint(4, -4),
        const _GridPoint(6, -2),
        const _GridPoint(6, 4),
        const _GridPoint(4, 6),
        const _GridPoint(-4, 6),
        const _GridPoint(-6, 4),
        const _GridPoint(-6, -4),
      ],
      <_GridPoint>[
        const _GridPoint(-4, -2),
        const _GridPoint(2, -2),
        const _GridPoint(4, 0),
        const _GridPoint(4, 3),
        const _GridPoint(2, 4),
        const _GridPoint(-3, 4),
        const _GridPoint(-4, 3),
        const _GridPoint(-4, -2),
      ],
    ];

    for (var index = 0; index < loops.length; index++) {
      final controls = loops[index]
          .map((point) => _iso(point.x, point.y, 1 + index))
          .toList();
      final lane = _polyline(controls);
      _roadLanes.add(lane);
      _stroke(lane, index == 0 ? _Tone.orangeDim : _Tone.violet, sparse: true);

      final pulseCount = index == 0 ? 5 : 3;
      for (var pulse = 0; pulse < pulseCount; pulse++) {
        final offset = _positiveMod(
          tick * (2 + index) + pulse * math.max(8, lane.length ~/ pulseCount).toInt(),
          lane.length,
        );
        _movingPulse(lane, offset, radius: 2, hot: pulse.isEven);
      }
    }
  }

  void _drawBuildings() {
    final buildings = <_Building>[
      const _Building(-6, -5, 2, 2, 11, 3),
      const _Building(-3, -6, 2, 2, 16, 7),
      const _Building(1, -6, 2, 2, 13, 11),
      const _Building(4, -5, 2, 2, 18, 17),
      const _Building(6, -2, 2, 2, 12, 23),
      const _Building(6, 2, 2, 2, 15, 29),
      const _Building(4, 5, 2, 2, 11, 31),
      const _Building(1, 6, 2, 2, 14, 37),
      const _Building(-3, 6, 2, 2, 12, 41),
      const _Building(-6, 4, 2, 2, 17, 43),
      const _Building(-6, 0, 2, 2, 10, 47),
      const _Building(-3, -3, 2, 2, 9, 53),
      const _Building(1, -3, 2, 2, 8, 59),
      const _Building(3, 1, 2, 2, 9, 61),
      const _Building(1, 4, 2, 2, 8, 67),
      const _Building(-3, 3, 2, 2, 9, 71),
    ];

    buildings.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    for (final building in buildings) {
      _drawBuilding(building);
    }
  }

  void _drawBuilding(_Building building) {
    final animatedHeight = building.height +
        (((tick ~/ 8 + building.seed) % 13 == 0 && hovered) ? 1 : 0);
    final topA = _iso(building.x, building.y, animatedHeight);
    final topB = _iso(building.x + building.sizeX, building.y, animatedHeight);
    final topC = _iso(
      building.x + building.sizeX,
      building.y + building.sizeY,
      animatedHeight,
    );
    final topD = _iso(building.x, building.y + building.sizeY, animatedHeight);
    final baseA = _iso(building.x, building.y, 0);
    final baseB = _iso(building.x + building.sizeX, building.y, 0);
    final baseC = _iso(
      building.x + building.sizeX,
      building.y + building.sizeY,
      0,
    );
    final baseD = _iso(building.x, building.y + building.sizeY, 0);

    _stroke(_polyline(<_Point>[topA, topB, topC, topD, topA]), _Tone.violet);
    _stroke(_line(topA, baseA), _Tone.violetDim);
    _stroke(_line(topB, baseB), _Tone.violetDim);
    _stroke(_line(topC, baseC), _Tone.violet);
    _stroke(_line(topD, baseD), _Tone.violetDim);
    _stroke(_line(baseB, baseC), _Tone.depth);
    _stroke(_line(baseC, baseD), _Tone.depth);

    final roofCenter = _Point(
      (topA.x + topB.x + topC.x + topD.x) ~/ 4,
      (topA.y + topB.y + topC.y + topD.y) ~/ 4,
    );
    canvas.set(roofCenter.x, roofCenter.y, '◆', _Tone.pink);
    _roofNodes.add(roofCenter);

    final antennaHeight = 2 + building.seed % 4;
    canvas.vLine(
      roofCenter.x,
      roofCenter.y - antennaHeight,
      roofCenter.y - 1,
      '│',
      _Tone.violetDim,
    );
    canvas.set(
      roofCenter.x,
      roofCenter.y - antennaHeight - 1,
      (tick + building.seed) % 8 < 2 ? '*' : '^',
      (tick + building.seed) % 8 < 2 ? _Tone.white : _Tone.violet,
    );

    _windowsOnEdge(topB, baseB, topC, baseC, building.seed);
    _windowsOnEdge(topD, baseD, topC, baseC, building.seed + 17);
  }

  void _windowsOnEdge(
    _Point topStart,
    _Point baseStart,
    _Point topEnd,
    _Point baseEnd,
    int seed,
  ) {
    final verticalSteps = math.max(3, (baseStart.y - topStart.y).abs() ~/ 2).toInt();
    for (var row = 1; row < verticalSteps; row++) {
      final t = row / verticalSteps;
      final left = _lerp(topStart, baseStart, t);
      final right = _lerp(topEnd, baseEnd, t);
      final line = _line(left, right);
      for (var index = 1; index < line.length - 1; index += 3) {
        final point = line[index];
        final hash = _noise(point.x, point.y, seed + tick ~/ 10);
        if (hash % 5 == 0) continue;
        canvas.set(
          point.x,
          point.y,
          hash % 7 == 0 ? '▥' : '·',
          hash % 4 == 0 ? _Tone.orange : _Tone.pink,
        );
      }
    }
  }

  _Point _drawCorePlatform() {
    const size = 4;
    const height = 4;
    const x = -2;
    const y = -2;
    final topA = _iso(x, y, height);
    final topB = _iso(x + size, y, height);
    final topC = _iso(x + size, y + size, height);
    final topD = _iso(x, y + size, height);
    final baseA = _iso(x, y, 0);
    final baseB = _iso(x + size, y, 0);
    final baseC = _iso(x + size, y + size, 0);
    final baseD = _iso(x, y + size, 0);

    _stroke(_polyline(<_Point>[topA, topB, topC, topD, topA]), _Tone.violet);
    _stroke(_line(topA, baseA), _Tone.violetDim);
    _stroke(_line(topB, baseB), _Tone.violetDim);
    _stroke(_line(topC, baseC), _Tone.violet);
    _stroke(_line(topD, baseD), _Tone.violetDim);
    _stroke(_line(baseB, baseC), _Tone.orangeDim);
    _stroke(_line(baseC, baseD), _Tone.orangeDim);

    final center = _Point(
      (topA.x + topB.x + topC.x + topD.x) ~/ 4,
      (topA.y + topB.y + topC.y + topD.y) ~/ 4,
    );
    canvas.write(center.x - 3, center.y + 2, 'CINDER', _Tone.white);

    for (var ring = 0; ring < 3; ring++) {
      final path = _polyline(<_Point>[
        _iso(x - ring, y - ring, 1 + ring),
        _iso(x + size + ring, y - ring, 1 + ring),
        _iso(x + size + ring, y + size + ring, 1 + ring),
        _iso(x - ring, y + size + ring, 1 + ring),
        _iso(x - ring, y - ring, 1 + ring),
      ]);
      _stroke(
        path,
        ring.isEven ? _Tone.orangeDim : _Tone.violetDim,
        sparse: true,
        phase: ring + tick ~/ 4,
      );
    }

    return _Point(center.x, center.y - 1);
  }

  void _drawPowerNetwork(_Point core) {
    if (_roofNodes.isEmpty) return;
    final step = math.max(1, _roofNodes.length ~/ 8).toInt();

    for (var index = 0; index < _roofNodes.length; index += step) {
      final node = _roofNodes[index];
      final side = node.x < core.x ? -1 : 1;
      final bend = _Point(
        core.x + side * (8 + (index % 3) * 4),
        math.min(core.y - 5, node.y + 3 + index % 3).toInt(),
      );
      final path = _polyline(<_Point>[
        node,
        _Point(node.x, node.y + 2),
        bend,
        _Point(core.x + side * 3, core.y - 2),
        core,
      ]);
      _powerLines.add(path);
      _stroke(path, _Tone.violetDim, sparse: true, phase: index);

      final speed = surging ? 5 : 2 + (energy * 1.4).round();
      final offset = _positiveMod(tick * speed + index * 13, path.length);
      _movingPulse(path, offset, radius: surging ? 5 : 3, hot: index.isEven);
      if (hovered || surging) {
        _movingPulse(
          path,
          _positiveMod(offset + path.length ~/ 2, path.length),
          radius: 2,
          hot: !index.isEven,
        );
      }
    }
  }

  void _drawElectricArcs() {
    if (_powerLines.length < 2) return;
    final count = surging
        ? math.min(7, _powerLines.length - 1).toInt()
        : math.min(3, _powerLines.length - 1).toInt();

    for (var index = 0; index < count; index++) {
      if (!surging && (tick + index * 5) % 16 > 4) continue;
      final first = _powerLines[index];
      final second = _powerLines[index + 1];
      final firstIndex = _positiveMod(tick * 2 + index * 7, first.length);
      final secondIndex = _positiveMod(
        second.length - 1 - tick * 2 - index * 9,
        second.length,
      );
      final start = first[firstIndex];
      final end = second[secondIndex];
      if ((start.x - end.x).abs() > math.max(18, width ~/ 5).toInt()) {
        continue;
      }
      if ((start.y - end.y).abs() > math.max(9, height ~/ 4).toInt()) {
        continue;
      }
      _jaggedArc(start, end, index * 101 + tick ~/ 2);
    }
  }

  void _jaggedArc(_Point start, _Point end, int seed) {
    final segments = math.max(
      3,
      math.min(9, (start.x - end.x).abs() ~/ 3 + 3),
    ).toInt();
    final controls = <_Point>[start];
    for (var index = 1; index < segments; index++) {
      final t = index / segments;
      final x = (start.x + (end.x - start.x) * t).round();
      final y = (start.y + (end.y - start.y) * t).round();
      final jitter = (_noise(x, y, seed + index) % 5) - 2;
      controls.add(_Point(x, y + jitter));
    }
    controls.add(end);

    final path = _polyline(controls);
    for (var index = 0; index < path.length; index++) {
      final point = path[index];
      canvas.set(
        point.x,
        point.y,
        index % 3 == 0 ? '*' : index.isEven ? '╱' : '╲',
        index % 3 == 0 ? _Tone.white : _Tone.glow,
      );
      if (surging && index % 4 == 0) {
        canvas.set(point.x - 1, point.y, '·', _Tone.pink);
        canvas.set(point.x + 1, point.y, '·', _Tone.pink);
      }
    }
  }

  void _drawFlame(_Point core) {
    final top = math.max(2, height ~/ 12).toInt();
    final bottom = core.y - 2;
    final amplitude = surging ? 1.55 : hovered ? 1.2 : 1;

    for (var y = bottom; y >= top; y--) {
      final progress = (bottom - y) / math.max(1, bottom - top);
      final wave = math.sin(y * 0.76 + tick * 0.31) * 2.2;
      final turbulence = (_noise(core.x, y, tick ~/ 2) % 7) - 3;
      final center = core.x + ((wave + turbulence * 0.42) * amplitude).round();
      final radius = math.max(
        1,
        2 + ((1 - progress) * math.max(2, width ~/ 44)).round() +
            ((_noise(y, tick, 83) % 3) - 1) +
            (surging ? 1 : 0),
      ).toInt();

      for (var x = center - radius - 2; x <= center + radius + 2; x++) {
        final distance = (x - center).abs();
        final heat = _noise(x, y, tick + y * 5);
        if (distance > radius && heat % 4 != 0) continue;

        if (distance == 0 || (distance <= 1 && heat % 3 != 0)) {
          canvas.set(x, y, heat.isEven ? '#' : '*', _Tone.white);
        } else if (distance <= math.max(1, radius ~/ 2).toInt()) {
          canvas.set(
            x,
            y,
            const <String>['#', '*', '+'][heat % 3],
            _Tone.glow,
          );
        } else if (distance <= radius) {
          canvas.set(
            x,
            y,
            const <String>['*', '+', ':'][heat % 3],
            _Tone.orange,
          );
        } else {
          canvas.set(x, y, heat.isEven ? '·' : ':', _Tone.pink);
        }
      }
    }

    for (var ring = 0; ring < (surging ? 4 : 2); ring++) {
      final radius = 4 + _positiveMod(tick + ring * 7, math.max(5, width ~/ 10).toInt());
      for (var dx = -radius; dx <= radius; dx++) {
        final dy = (radius - dx.abs()) ~/ 3;
        if (_noise(dx, dy, tick + ring) % 4 != 0) continue;
        canvas.set(core.x + dx, core.y + dy, '·', ring.isEven ? _Tone.pink : _Tone.orange);
        canvas.set(core.x + dx, core.y - dy, '·', ring.isEven ? _Tone.pink : _Tone.orange);
      }
    }
  }

  void _drawTraffic() {
    for (var laneIndex = 0; laneIndex < _roadLanes.length; laneIndex++) {
      final lane = _roadLanes[laneIndex];
      if (lane.isEmpty) continue;
      final count = math.max(3, width ~/ 42).toInt();
      for (var vehicle = 0; vehicle < count; vehicle++) {
        final offset = _positiveMod(
          tick * (2 + laneIndex) +
              vehicle * math.max(9, lane.length ~/ count).toInt(),
          lane.length,
        );
        final head = lane[offset];
        final tail = lane[_positiveMod(offset - 1, lane.length)];
        canvas.set(head.x, head.y, laneIndex.isEven ? '>' : '<', _Tone.white);
        canvas.set(tail.x, tail.y, '─', _Tone.orange);
      }
    }
  }

  void _drawParticles(_Point core) {
    final count = math.max(10, width * height ~/ 520).toInt();
    for (var index = 0; index < count; index++) {
      final seed = _noise(index, tick ~/ 2, 131);
      final x = _positiveMod(seed * 13 + tick * (index.isEven ? 1 : -1), width);
      final y = _positiveMod(seed * 7 - tick + index * 11, height);
      if ((x - core.x).abs() < width ~/ 4 && y < core.y + 7) {
        canvas.set(
          x,
          y,
          seed.isEven ? '·' : '+',
          seed % 3 == 0 ? _Tone.glow : _Tone.pink,
        );
      }
    }
  }

  void _drawDrone() {
    if (width < 78 || height < 28) return;
    final span = math.max(12, width - 38).toInt();
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 19 + travel : 19 + (span * 2 - travel);
    final y = math.max(6, height ~/ 3 + (math.sin(tick * 0.13) * 2).round()).toInt();
    final right = travel < span;
    canvas.write(x - 2, y, right ? '─[>]' : '[<]─', _Tone.white);
    canvas.set(right ? x - 3 : x + 3, y, '·', _Tone.orange);
  }

  void _movingPulse(
    List<_Point> path,
    int center, {
    required int radius,
    required bool hot,
  }) {
    if (path.isEmpty) return;
    for (var offset = -radius; offset <= radius; offset++) {
      final point = path[_positiveMod(center + offset, path.length)];
      final distance = offset.abs();
      if (distance == 0) {
        canvas.set(point.x, point.y, '*', _Tone.white);
      } else if (distance == 1) {
        canvas.set(point.x, point.y, hot ? '#' : '+', _Tone.glow);
      } else {
        canvas.set(
          point.x,
          point.y,
          distance.isEven ? ':' : '·',
          hot ? _Tone.orange : _Tone.pink,
        );
      }
    }
  }

  _Point _iso(int gridX, int gridY, int z) {
    return _Point(
      _originX + (gridX - gridY) * _tileX,
      _originY + (gridX + gridY) * _tileY - z,
    );
  }

  _Point _lerp(_Point a, _Point b, double t) {
    return _Point(
      (a.x + (b.x - a.x) * t).round(),
      (a.y + (b.y - a.y) * t).round(),
    );
  }

  List<_Point> _polyline(List<_Point> controls) {
    final result = <_Point>[];
    if (controls.isEmpty) return result;
    result.add(controls.first);
    for (var index = 1; index < controls.length; index++) {
      final segment = _line(controls[index - 1], controls[index]);
      if (segment.isNotEmpty) result.addAll(segment.skip(1));
    }
    return result;
  }

  List<_Point> _line(_Point start, _Point end) {
    final points = <_Point>[];
    var x0 = start.x;
    var y0 = start.y;
    final x1 = end.x;
    final y1 = end.y;
    final dx = (x1 - x0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs();
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;

    while (true) {
      points.add(_Point(x0, y0));
      if (x0 == x1 && y0 == y1) break;
      final doubled = 2 * error;
      if (doubled >= dy) {
        error += dy;
        x0 += sx;
      }
      if (doubled <= dx) {
        error += dx;
        y0 += sy;
      }
    }

    return points;
  }

  void _stroke(
    List<_Point> path,
    int tone, {
    bool sparse = false,
    int phase = 0,
  }) {
    for (var index = 0; index < path.length; index++) {
      if (sparse && (index + phase + tick ~/ 5) % 7 == 0) continue;
      final previous = index > 0 ? path[index - 1] : path[index];
      final next = index < path.length - 1 ? path[index + 1] : path[index];
      canvas.set(path[index].x, path[index].y, _pathGlyph(previous, next), tone);
    }
  }

  String _pathGlyph(_Point previous, _Point next) {
    final dx = next.x - previous.x;
    final dy = next.y - previous.y;
    if (dx == 0) return '│';
    if (dy == 0) return '─';
    return dx.sign == dy.sign ? '╲' : '╱';
  }

  int _noise(int x, int y, int seed) {
    var value = x * 374761393 + y * 668265263 + seed * 69069;
    value = (value ^ (value >> 13)) * 1274126177;
    return (value ^ (value >> 16)) & 0x7fffffff;
  }

  int _positiveMod(int value, int modulus) {
    if (modulus <= 0) return 0;
    final result = value % modulus;
    return result < 0 ? result + modulus : result;
  }
}

class _WorldCanvas {
  _WorldCanvas(this.width, this.height)
      : _rows = List<List<_Cell>>.generate(
          height,
          (_) => List<_Cell>.generate(
            width,
            (_) => const _Cell(' ', _Tone.empty),
            growable: false,
          ),
          growable: false,
        );

  final int width;
  final int height;
  final List<List<_Cell>> _rows;

  void set(int x, int y, String glyph, int tone) {
    if (x < 0 || x >= width || y < 0 || y >= height || glyph.isEmpty) return;
    if (tone < _rows[y][x].tone) return;
    _rows[y][x] = _Cell(glyph, tone);
  }

  void write(int x, int y, String text, int tone) {
    for (var index = 0; index < text.length; index++) {
      set(x + index, y, text[index], tone);
    }
  }

  void hLine(int startX, int endX, int y, String glyph, int tone) {
    final left = math.min(startX, endX).toInt();
    final right = math.max(startX, endX).toInt();
    for (var x = left; x <= right; x++) {
      set(x, y, glyph, tone);
    }
  }

  void vLine(int x, int startY, int endY, String glyph, int tone) {
    final top = math.min(startY, endY).toInt();
    final bottom = math.max(startY, endY).toInt();
    for (var y = top; y <= bottom; y++) {
      set(x, y, glyph, tone);
    }
  }

  TextSpan toTextSpan() {
    final spans = <InlineSpan>[];

    for (var y = 0; y < height; y++) {
      var activeTone = _Tone.empty;
      var buffer = StringBuffer();

      void flush() {
        if (buffer.length == 0) return;
        spans.add(
          TextSpan(
            text: buffer.toString(),
            style: _Palette.styleFor(activeTone),
          ),
        );
        buffer = StringBuffer();
      }

      for (var x = 0; x < width; x++) {
        final cell = _rows[y][x];
        if (cell.tone != activeTone) {
          flush();
          activeTone = cell.tone;
        }
        buffer.write(cell.glyph);
      }
      flush();
      if (y < height - 1) spans.add(const TextSpan(text: '\n'));
    }

    return TextSpan(children: spans);
  }
}

class _Cell {
  const _Cell(this.glyph, this.tone);

  final String glyph;
  final int tone;
}

class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}

class _GridPoint {
  const _GridPoint(this.x, this.y);

  final int x;
  final int y;
}

class _Building {
  const _Building(
    this.x,
    this.y,
    this.sizeX,
    this.sizeY,
    this.height,
    this.seed,
  );

  final int x;
  final int y;
  final int sizeX;
  final int sizeY;
  final int height;
  final int seed;
}

abstract class _Tone {
  static const int empty = 0;
  static const int star = 1;
  static const int depth = 2;
  static const int violetDim = 3;
  static const int orangeDim = 4;
  static const int violet = 5;
  static const int orange = 6;
  static const int pink = 7;
  static const int glow = 8;
  static const int white = 9;
}

abstract class _Palette {
  static const Color background = Color.fromRGB(2, 3, 8);
  static const Color star = Color.fromRGB(72, 47, 91);
  static const Color depth = Color.fromRGB(48, 37, 67);
  static const Color violetDim = Color.fromRGB(93, 57, 129);
  static const Color orangeDim = Color.fromRGB(139, 67, 25);
  static const Color violet = Color.fromRGB(185, 83, 244);
  static const Color orange = Color.fromRGB(239, 111, 30);
  static const Color pink = Color.fromRGB(255, 64, 183);
  static const Color glow = Color.fromRGB(255, 174, 63);
  static const Color white = Color.fromRGB(255, 242, 226);

  static TextStyle? styleFor(int tone) {
    return switch (tone) {
      _Tone.star => const TextStyle(color: star, fontWeight: FontWeight.dim),
      _Tone.depth => const TextStyle(color: depth, fontWeight: FontWeight.dim),
      _Tone.violetDim =>
        const TextStyle(color: violetDim, fontWeight: FontWeight.dim),
      _Tone.orangeDim =>
        const TextStyle(color: orangeDim, fontWeight: FontWeight.dim),
      _Tone.violet =>
        const TextStyle(color: violet, fontWeight: FontWeight.bold),
      _Tone.orange =>
        const TextStyle(color: orange, fontWeight: FontWeight.bold),
      _Tone.pink => const TextStyle(color: pink, fontWeight: FontWeight.bold),
      _Tone.glow => const TextStyle(color: glow, fontWeight: FontWeight.bold),
      _Tone.white => const TextStyle(color: white, fontWeight: FontWeight.bold),
      _ => null,
    };
  }
}
