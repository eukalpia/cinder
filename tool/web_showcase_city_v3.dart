import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// Compact, living Cinder metropolis for the website dashboard.
void main() {
  runApp(const CinderApp(child: CinderCityV3()));
}

class CinderCityV3 extends StatefulWidget {
  const CinderCityV3({super.key});

  @override
  State<CinderCityV3> createState() => _CinderCityV3State();
}

class _CinderCityV3State extends State<CinderCityV3> {
  Timer? _ticker;
  int _tick = 0;
  int _surgeUntil = 0;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted) return;
      setState(() => _tick++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => setState(() => _surgeUntil = _tick + 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = _extent(constraints.maxWidth, 126, 196);
            final height = _extent(constraints.maxHeight, 50, 82);
            final scene = _Metropolis(
              width: width,
              height: height,
              tick: _tick,
              hovered: _hovered,
              surging: _tick < _surgeUntil,
            ).render();

            return Container(
              color: _Palette.background,
              child: RichText(
                text: scene.toTextSpan(),
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            );
          },
        ),
      ),
    );
  }

  int _extent(double value, int fallback, int maximum) {
    if (!value.isFinite || value <= 0) return fallback;
    return value.floor().clamp(1, maximum).toInt();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class _Metropolis {
  _Metropolis({
    required this.width,
    required this.height,
    required this.tick,
    required this.hovered,
    required this.surging,
  }) : canvas = _Canvas(width, height);

  final int width;
  final int height;
  final int tick;
  final bool hovered;
  final bool surging;
  final _Canvas canvas;

  final List<_Point> _nodes = <_Point>[];
  final List<List<_Point>> _wires = <List<_Point>>[];
  final List<List<_Point>> _roads = <List<_Point>>[];

  _Canvas render() {
    if (width < 44 || height < 20) {
      _compact();
      return canvas;
    }

    _stars();
    _hud();
    _roadsBehind();
    _backBuildings();
    _middleBuildings();
    _roadsFront();
    _frontBuildings();
    final core = _core();
    _wireGrid(core);
    _electricity();
    _fire(core);
    _traffic();
    _particles(core);
    _drone();
    return canvas;
  }

  void _compact() {
    final cx = width ~/ 2;
    final base = height - 2;
    for (var y = base - 4; y > 1; y--) {
      final sway = (math.sin(y * 0.8 + tick * 0.3) * 2).round();
      final radius = y > base - 10 ? 3 : y > base - 16 ? 2 : 1;
      for (var x = cx + sway - radius; x <= cx + sway + radius; x++) {
        final d = (x - cx - sway).abs();
        canvas.set(
          x,
          y,
          d == 0 ? '#' : d == 1 ? '*' : '·',
          d == 0 ? _Tone.white : d == 1 ? _Tone.glow : _Tone.pink,
        );
      }
    }
    canvas.write(cx - 9, base - 2, '╭──────CINDER─────╮', _Tone.violet);
    canvas.write(cx - 9, base - 1, '╰─────────────────╯', _Tone.orange);
  }

  void _stars() {
    final phase = tick ~/ 9;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final n = _noise(x, y, phase);
        if (n % 401 == 0) canvas.set(x, y, n.isEven ? '·' : '.', _Tone.star);
        if (n % 1031 == 0) canvas.set(x, y, tick.isEven ? '+' : '×', _Tone.pink);
      }
    }
  }

  void _hud() {
    if (width < 98 || height < 38) return;
    _panel(2, 2, 12, 'STATE', 'CORE');
    _panel(width - 14, 2, 12, 'DIFF', 'MIN');
    _panel(2, height - 7, 15, 'EVENTS', 'PULSE');
    _panel(width - 17, height - 7, 15, 'FRAME', 'SYNC');
  }

  void _panel(int x, int y, int w, String title, String value) {
    canvas.set(x, y, '╭', _Tone.violetDim);
    canvas.hLine(x + 1, x + w - 2, y, '─', _Tone.violetDim);
    canvas.set(x + w - 1, y, '╮', _Tone.violetDim);
    canvas.vLine(x, y + 1, y + 3, '│', _Tone.violetDim);
    canvas.vLine(x + w - 1, y + 1, y + 3, '│', _Tone.violetDim);
    canvas.set(x, y + 4, '╰', _Tone.violetDim);
    canvas.hLine(x + 1, x + w - 2, y + 4, '─', _Tone.violetDim);
    canvas.set(x + w - 1, y + 4, '╯', _Tone.violetDim);
    canvas.write(x + 2, y + 1, title, _Tone.orange);
    canvas.write(x + 2, y + 2, value, _Tone.violet);
    canvas.write(x + 2, y + 3, 'LIVE', _Tone.pink);
  }

  void _backBuildings() {
    final base = math.max(20, (height * 0.43).round()).toInt();
    _nodes.add(_box(width * 9 ~/ 100, base, 5, 8, 2, 11, _Tone.depth));
    _nodes.add(_box(width * 22 ~/ 100, base - 2, 6, 13, 3, 17, _Tone.violetDim));
    _nodes.add(_box(width * 35 ~/ 100, base, 5, 9, 2, 19, _Tone.depth));
    _nodes.add(_box(width * 65 ~/ 100, base, 5, 9, 2, 23, _Tone.depth));
    _nodes.add(_box(width * 78 ~/ 100, base - 2, 6, 13, 3, 29, _Tone.violetDim));
    _nodes.add(_box(width * 91 ~/ 100, base, 5, 8, 2, 31, _Tone.depth));
  }

  void _middleBuildings() {
    final base = math.max(30, (height * 0.65).round()).toInt();
    _nodes.add(_box(width * 7 ~/ 100, base, 7, 13, 3, 37, _Tone.violetDim));
    _nodes.add(_box(width * 21 ~/ 100, base - 1, 8, 12, 3, 41, _Tone.violet));
    _nodes.add(_box(width * 34 ~/ 100, base + 1, 7, 10, 3, 43, _Tone.violetDim));
    _nodes.add(_box(width * 66 ~/ 100, base + 1, 7, 10, 3, 47, _Tone.violetDim));
    _nodes.add(_box(width * 79 ~/ 100, base - 1, 8, 12, 3, 53, _Tone.violet));
    _nodes.add(_box(width * 93 ~/ 100, base, 7, 13, 3, 59, _Tone.violetDim));
  }

  void _frontBuildings() {
    final base = height - 3;
    _nodes.add(_box(width * 13 ~/ 100, base, 10, 16, 4, 61, _Tone.violet));
    _nodes.add(_box(width * 31 ~/ 100, base - 1, 10, 12, 4, 67, _Tone.violet));
    _nodes.add(_box(width * 69 ~/ 100, base - 1, 10, 12, 4, 71, _Tone.violet));
    _nodes.add(_box(width * 87 ~/ 100, base, 10, 16, 4, 73, _Tone.violet));
  }

  _Point _box(
    int cx,
    int baseY,
    int halfWidth,
    int bodyHeight,
    int depth,
    int seed,
    int wallTone,
  ) {
    final roofY = baseY - bodyHeight;
    final frontLeft = _Point(cx - halfWidth, roofY);
    final frontRight = _Point(cx + halfWidth, roofY);
    final backLeft = _Point(cx - halfWidth + depth * 2, roofY - depth);
    final backRight = _Point(cx + halfWidth + depth * 2, roofY - depth);
    final bottomLeft = _Point(frontLeft.x, frontLeft.y + bodyHeight);
    final bottomRight = _Point(frontRight.x, frontRight.y + bodyHeight);
    final backBottomRight = _Point(backRight.x, backRight.y + bodyHeight);

    _stroke(
      _polyline(<_Point>[
        backLeft,
        backRight,
        frontRight,
        frontLeft,
        backLeft,
      ]),
      _Tone.violet,
    );
    _stroke(_line(frontLeft, bottomLeft), wallTone);
    _stroke(_line(frontRight, bottomRight), _Tone.violet);
    _stroke(_line(backRight, backBottomRight), wallTone);
    _stroke(_line(bottomLeft, bottomRight), _Tone.depth);
    _stroke(_line(bottomRight, backBottomRight), _Tone.depth);

    final floors = math.max(2, bodyHeight ~/ 3).toInt();
    for (var floor = 1; floor < floors; floor++) {
      final t = floor / floors;
      final left = _lerp(frontLeft, bottomLeft, t);
      final right = _lerp(frontRight, bottomRight, t);
      final backRightFloor = _lerp(backRight, backBottomRight, t);
      final front = _line(left, right);
      final side = _line(right, backRightFloor);
      _stroke(front, _Tone.depth);
      _stroke(side, wallTone);
      _windows(front, seed + floor * 13);
      _windows(side, seed + floor * 17);
    }

    _column(frontLeft, frontRight, bottomLeft, bottomRight, 0.34, wallTone);
    _column(frontLeft, frontRight, bottomLeft, bottomRight, 0.67, wallTone);
    _column(frontRight, backRight, bottomRight, backBottomRight, 0.5, wallTone);

    final roofCenter = _Point(cx + depth, roofY - depth ~/ 2);
    canvas.set(roofCenter.x, roofCenter.y, '◆', _Tone.pink);
    final antenna = 2 + seed % 4;
    canvas.vLine(roofCenter.x, roofCenter.y - antenna, roofCenter.y - 1, '│', _Tone.violetDim);
    canvas.set(
      roofCenter.x,
      roofCenter.y - antenna - 1,
      (tick + seed) % 9 < 2 ? '*' : '^',
      (tick + seed) % 9 < 2 ? _Tone.white : _Tone.violet,
    );

    if (halfWidth >= 8) {
      _roofUnit(cx - halfWidth ~/ 3 + depth, roofY - 1, 3, seed);
      _roofUnit(cx + halfWidth ~/ 3 + depth, roofY - 1, 2, seed + 5);
    }

    return _Point(roofCenter.x, roofCenter.y - antenna - 1);
  }

  void _roofUnit(int cx, int baseY, int unitHeight, int seed) {
    final top = baseY - unitHeight;
    canvas.set(cx - 2, top, '╭', _Tone.violetDim);
    canvas.hLine(cx - 1, cx + 1, top, '─', _Tone.violetDim);
    canvas.set(cx + 2, top, '╮', _Tone.violetDim);
    canvas.vLine(cx - 2, top + 1, baseY - 1, '│', _Tone.depth);
    canvas.vLine(cx + 2, top + 1, baseY - 1, '│', _Tone.violetDim);
    canvas.set(cx, top, seed.isEven ? '·' : '◆', _Tone.pink);
  }

  void _column(
    _Point topA,
    _Point topB,
    _Point bottomA,
    _Point bottomB,
    double fraction,
    int tone,
  ) {
    final top = _lerp(topA, topB, fraction);
    final bottom = _lerp(bottomA, bottomB, fraction);
    _stroke(_line(top, bottom), tone, sparse: true, phase: (fraction * 10).round());
  }

  void _windows(List<_Point> edge, int seed) {
    for (var index = 2; index < edge.length - 1; index += 3) {
      final p = edge[index];
      final n = _noise(p.x, p.y, seed + tick ~/ 11);
      if (n % 5 == 0) continue;
      canvas.set(
        p.x,
        p.y,
        n % 7 == 0 ? '▥' : '·',
        n % 4 == 0 ? _Tone.orange : _Tone.pink,
      );
    }
  }

  void _roadsBehind() {
    final y = math.max(18, (height * 0.45).round()).toInt();
    final outer = _polyline(<_Point>[
      _Point(0, y + 3),
      _Point(width * 18 ~/ 100, y - 1),
      _Point(width * 36 ~/ 100, y + 5),
      _Point(width ~/ 2, y + 1),
      _Point(width * 64 ~/ 100, y + 5),
      _Point(width * 82 ~/ 100, y - 1),
      _Point(width - 1, y + 3),
    ]);
    final inner = _polyline(<_Point>[
      _Point(width * 10 ~/ 100, y + 8),
      _Point(width * 28 ~/ 100, y + 3),
      _Point(width ~/ 2, y + 8),
      _Point(width * 72 ~/ 100, y + 3),
      _Point(width * 90 ~/ 100, y + 8),
    ]);
    _roads.add(outer);
    _roads.add(inner);
    _stroke(outer, _Tone.violetDim, sparse: true, phase: 1);
    _stroke(inner, _Tone.orangeDim, sparse: true, phase: 4);
  }

  void _roadsFront() {
    final y = math.max(29, (height * 0.7).round()).toInt();
    final outer = _polyline(<_Point>[
      _Point(0, y - 1),
      _Point(width * 20 ~/ 100, y + 5),
      _Point(width * 38 ~/ 100, y + 1),
      _Point(width ~/ 2, y + 6),
      _Point(width * 62 ~/ 100, y + 1),
      _Point(width * 80 ~/ 100, y + 5),
      _Point(width - 1, y - 1),
    ]);
    final inner = _polyline(<_Point>[
      _Point(width * 8 ~/ 100, height - 4),
      _Point(width * 28 ~/ 100, y + 5),
      _Point(width ~/ 2, height - 5),
      _Point(width * 72 ~/ 100, y + 5),
      _Point(width * 92 ~/ 100, height - 4),
    ]);
    _roads.add(outer);
    _roads.add(inner);
    _stroke(outer, _Tone.orangeDim, sparse: true, phase: 2);
    _stroke(inner, _Tone.violet, sparse: true, phase: 5);
  }

  _Point _core() {
    final cx = width ~/ 2;
    final baseY = height - 8;
    const halfWidth = 15;
    const bodyHeight = 8;
    const depth = 5;
    final roofY = baseY - bodyHeight;
    final frontLeft = _Point(cx - halfWidth, roofY);
    final frontRight = _Point(cx + halfWidth, roofY);
    final backLeft = _Point(cx - halfWidth + depth * 2, roofY - depth);
    final backRight = _Point(cx + halfWidth + depth * 2, roofY - depth);
    final bottomLeft = _Point(frontLeft.x, frontLeft.y + bodyHeight);
    final bottomRight = _Point(frontRight.x, frontRight.y + bodyHeight);
    final backBottomRight = _Point(backRight.x, backRight.y + bodyHeight);

    _stroke(
      _polyline(<_Point>[
        backLeft,
        backRight,
        frontRight,
        frontLeft,
        backLeft,
      ]),
      _Tone.violet,
    );
    _stroke(_line(frontLeft, bottomLeft), _Tone.violetDim);
    _stroke(_line(frontRight, bottomRight), _Tone.violet);
    _stroke(_line(backRight, backBottomRight), _Tone.violetDim);
    _stroke(_line(bottomLeft, bottomRight), _Tone.orangeDim);
    _stroke(_line(bottomRight, backBottomRight), _Tone.orangeDim);

    final floorLeft = _lerp(frontLeft, bottomLeft, 0.55);
    final floorRight = _lerp(frontRight, bottomRight, 0.55);
    final floorBack = _lerp(backRight, backBottomRight, 0.55);
    _stroke(_line(floorLeft, floorRight), _Tone.depth);
    _stroke(_line(floorRight, floorBack), _Tone.violetDim);

    final center = _Point(cx + depth, roofY - depth ~/ 2);
    canvas.write(cx - 3, frontLeft.y + 3, 'CINDER', _Tone.white);
    canvas.set(center.x, center.y, '◆', _Tone.white);

    for (var ring = 0; ring < 3; ring++) {
      final expand = ring * 3;
      final path = _polyline(<_Point>[
        _Point(frontLeft.x - expand, frontLeft.y + ring),
        _Point(backLeft.x - expand, backLeft.y - ring),
        _Point(backRight.x + expand, backRight.y - ring),
        _Point(frontRight.x + expand, frontRight.y + ring),
      ]);
      _stroke(
        path,
        ring.isEven ? _Tone.orangeDim : _Tone.violetDim,
        sparse: true,
        phase: tick ~/ 4 + ring,
      );
    }

    return _Point(center.x, center.y - 1);
  }

  void _wireGrid(_Point core) {
    if (_nodes.isEmpty) return;
    final selected = <_Point>[];
    final stride = math.max(1, _nodes.length ~/ 7).toInt();
    for (var index = 0; index < _nodes.length; index += stride) {
      selected.add(_nodes[index]);
    }

    for (var index = 0; index < selected.length; index++) {
      final node = selected[index];
      final side = node.x < core.x ? -1 : 1;
      final bend = _Point(
        core.x + side * (10 + index % 3 * 4),
        math.min(core.y - 4, node.y + 4 + index % 3).toInt(),
      );
      final wire = _polyline(<_Point>[
        node,
        _Point(node.x, node.y + 2),
        bend,
        _Point(core.x + side * 3, core.y - 2),
        core,
      ]);
      _wires.add(wire);
      _stroke(wire, _Tone.violetDim, sparse: true, phase: index);
      final speed = surging ? 5 : 2;
      final pulse = _positiveMod(tick * speed + index * 17, wire.length);
      _pulse(wire, pulse, surging ? 5 : 3, index.isEven);
      if (hovered || surging) {
        _pulse(
          wire,
          _positiveMod(pulse + wire.length ~/ 2, wire.length),
          2,
          !index.isEven,
        );
      }
    }
  }

  void _electricity() {
    if (_wires.length < 2) return;
    final count = surging
        ? math.min(6, _wires.length - 1).toInt()
        : math.min(2, _wires.length - 1).toInt();
    for (var index = 0; index < count; index++) {
      if (!surging && (tick + index * 5) % 19 > 4) continue;
      final a = _wires[index];
      final b = _wires[index + 1];
      final start = a[_positiveMod(tick * 2 + index * 7, a.length)];
      final end = b[_positiveMod(b.length - 1 - tick * 2 - index * 9, b.length)];
      if ((start.x - end.x).abs() > math.max(20, width ~/ 5).toInt()) continue;
      if ((start.y - end.y).abs() > math.max(9, height ~/ 4).toInt()) continue;
      _arc(start, end, index * 101 + tick ~/ 2);
    }
  }

  void _arc(_Point start, _Point end, int seed) {
    final segments = math.max(
      3,
      math.min(9, (start.x - end.x).abs() ~/ 3 + 3),
    ).toInt();
    final controls = <_Point>[start];
    for (var index = 1; index < segments; index++) {
      final t = index / segments;
      final x = (start.x + (end.x - start.x) * t).round();
      final y = (start.y + (end.y - start.y) * t).round();
      controls.add(_Point(x, y + (_noise(x, y, seed + index) % 5) - 2));
    }
    controls.add(end);
    final path = _polyline(controls);
    for (var index = 0; index < path.length; index++) {
      final p = path[index];
      canvas.set(
        p.x,
        p.y,
        index % 3 == 0 ? '*' : index.isEven ? '╱' : '╲',
        index % 3 == 0 ? _Tone.white : _Tone.glow,
      );
      if (surging && index % 4 == 0) {
        canvas.set(p.x - 1, p.y, '·', _Tone.pink);
        canvas.set(p.x + 1, p.y, '·', _Tone.pink);
      }
    }
  }

  void _fire(_Point core) {
    final top = math.max(2, height ~/ 13).toInt();
    final bottom = core.y - 1;
    final amplitude = surging ? 1.5 : hovered ? 1.2 : 1;
    for (var y = bottom; y >= top; y--) {
      final progress = (bottom - y) / math.max(1, bottom - top);
      final wave = math.sin(y * 0.74 + tick * 0.31) * 2.1;
      final noise = (_noise(core.x, y, tick ~/ 2) % 7) - 3;
      final center = core.x + ((wave + noise * 0.4) * amplitude).round();
      final radius = math.max(
        1,
        2 +
            ((1 - progress) * math.max(2, width ~/ 48)).round() +
            ((_noise(y, tick, 83) % 3) - 1) +
            (surging ? 1 : 0),
      ).toInt();
      for (var x = center - radius - 2; x <= center + radius + 2; x++) {
        final d = (x - center).abs();
        final heat = _noise(x, y, tick + y * 5);
        if (d > radius && heat % 4 != 0) continue;
        if (d == 0 || (d <= 1 && heat % 3 != 0)) {
          canvas.set(x, y, heat.isEven ? '#' : '*', _Tone.white);
        } else if (d <= math.max(1, radius ~/ 2).toInt()) {
          canvas.set(x, y, const <String>['#', '*', '+'][heat % 3], _Tone.glow);
        } else if (d <= radius) {
          canvas.set(x, y, const <String>['*', '+', ':'][heat % 3], _Tone.orange);
        } else {
          canvas.set(x, y, heat.isEven ? '·' : ':', _Tone.pink);
        }
      }
    }
  }

  void _traffic() {
    for (var roadIndex = 0; roadIndex < _roads.length; roadIndex++) {
      final road = _roads[roadIndex];
      final count = math.max(2, width ~/ 48).toInt();
      for (var vehicle = 0; vehicle < count; vehicle++) {
        final offset = _positiveMod(
          tick * (2 + roadIndex % 3) +
              vehicle * math.max(8, road.length ~/ count).toInt(),
          road.length,
        );
        final head = road[offset];
        final tail = road[_positiveMod(offset - 1, road.length)];
        canvas.set(head.x, head.y, roadIndex.isEven ? '>' : '<', _Tone.white);
        canvas.set(tail.x, tail.y, '─', _Tone.orange);
      }
    }
  }

  void _particles(_Point core) {
    final count = math.max(9, width * height ~/ 720).toInt();
    for (var index = 0; index < count; index++) {
      final n = _noise(index, tick ~/ 2, 131);
      final x = _positiveMod(n * 13 + tick * (index.isEven ? 1 : -1), width);
      final y = _positiveMod(n * 7 - tick + index * 11, height);
      if ((x - core.x).abs() > width ~/ 3 || y > core.y + 8) continue;
      canvas.set(x, y, n.isEven ? '·' : '+', n % 3 == 0 ? _Tone.glow : _Tone.pink);
    }
  }

  void _drone() {
    if (width < 78 || height < 28) return;
    final span = math.max(12, width - 38).toInt();
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 19 + travel : 19 + (span * 2 - travel);
    final y = math.max(6, height ~/ 3 + (math.sin(tick * 0.13) * 2).round()).toInt();
    final right = travel < span;
    canvas.write(x - 2, y, right ? '─[>]' : '[<]─', _Tone.white);
    canvas.set(right ? x - 3 : x + 3, y, '·', _Tone.orange);
  }

  void _pulse(List<_Point> path, int center, int radius, bool hot) {
    if (path.isEmpty) return;
    for (var offset = -radius; offset <= radius; offset++) {
      final p = path[_positiveMod(center + offset, path.length)];
      final d = offset.abs();
      if (d == 0) {
        canvas.set(p.x, p.y, '*', _Tone.white);
      } else if (d == 1) {
        canvas.set(p.x, p.y, hot ? '#' : '+', _Tone.glow);
      } else {
        canvas.set(p.x, p.y, d.isEven ? ':' : '·', hot ? _Tone.orange : _Tone.pink);
      }
    }
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
    for (var i = 1; i < controls.length; i++) {
      final segment = _line(controls[i - 1], controls[i]);
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
    for (var i = 0; i < path.length; i++) {
      if (sparse && (i + phase + tick ~/ 5) % 7 == 0) continue;
      final previous = i > 0 ? path[i - 1] : path[i];
      final next = i < path.length - 1 ? path[i + 1] : path[i];
      canvas.set(path[i].x, path[i].y, _glyph(previous, next), tone);
    }
  }

  String _glyph(_Point previous, _Point next) {
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

class _Canvas {
  _Canvas(this.width, this.height)
      : rows = List<List<_Cell>>.generate(
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
  final List<List<_Cell>> rows;

  void set(int x, int y, String glyph, int tone) {
    if (x < 0 || x >= width || y < 0 || y >= height || glyph.isEmpty) return;
    if (tone < rows[y][x].tone) return;
    rows[y][x] = _Cell(glyph, tone);
  }

  void write(int x, int y, String text, int tone) {
    for (var i = 0; i < text.length; i++) set(x + i, y, text[i], tone);
  }

  void hLine(int startX, int endX, int y, String glyph, int tone) {
    for (var x = math.min(startX, endX); x <= math.max(startX, endX); x++) {
      set(x.toInt(), y, glyph, tone);
    }
  }

  void vLine(int x, int startY, int endY, String glyph, int tone) {
    for (var y = math.min(startY, endY); y <= math.max(startY, endY); y++) {
      set(x, y.toInt(), glyph, tone);
    }
  }

  TextSpan toTextSpan() {
    final spans = <InlineSpan>[];
    for (var y = 0; y < height; y++) {
      var activeTone = _Tone.empty;
      var buffer = StringBuffer();
      void flush() {
        if (buffer.length == 0) return;
        spans.add(TextSpan(text: buffer.toString(), style: _Palette.style(activeTone)));
        buffer = StringBuffer();
      }
      for (var x = 0; x < width; x++) {
        final cell = rows[y][x];
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
  static const Color star = Color.fromRGB(70, 45, 90);
  static const Color depth = Color.fromRGB(48, 37, 67);
  static const Color violetDim = Color.fromRGB(93, 57, 129);
  static const Color orangeDim = Color.fromRGB(143, 68, 25);
  static const Color violet = Color.fromRGB(185, 83, 244);
  static const Color orange = Color.fromRGB(239, 111, 30);
  static const Color pink = Color.fromRGB(255, 64, 183);
  static const Color glow = Color.fromRGB(255, 174, 63);
  static const Color white = Color.fromRGB(255, 242, 226);

  static TextStyle? style(int tone) {
    return switch (tone) {
      _Tone.star => const TextStyle(color: star, fontWeight: FontWeight.dim),
      _Tone.depth => const TextStyle(color: depth, fontWeight: FontWeight.dim),
      _Tone.violetDim => const TextStyle(color: violetDim, fontWeight: FontWeight.dim),
      _Tone.orangeDim => const TextStyle(color: orangeDim, fontWeight: FontWeight.dim),
      _Tone.violet => const TextStyle(color: violet, fontWeight: FontWeight.bold),
      _Tone.orange => const TextStyle(color: orange, fontWeight: FontWeight.bold),
      _Tone.pink => const TextStyle(color: pink, fontWeight: FontWeight.bold),
      _Tone.glow => const TextStyle(color: glow, fontWeight: FontWeight.bold),
      _Tone.white => const TextStyle(color: white, fontWeight: FontWeight.bold),
      _ => null,
    };
  }
}
