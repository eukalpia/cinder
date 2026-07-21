import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// A coherent, animated isometric terminal city rendered by Cinder.
///
/// The page hosts xterm.js, but Cinder owns every visible terminal cell,
/// animation frame, pointer reaction, resize pass, road light, cable pulse,
/// electric arc, building, window, and plasma particle.
void main() {
  runApp(const CinderApp(child: CinderCityV2()));
}

class CinderCityV2 extends StatefulWidget {
  const CinderCityV2({super.key});

  @override
  State<CinderCityV2> createState() => _CinderCityV2State();
}

class _CinderCityV2State extends State<CinderCityV2> {
  Timer? _ticker;
  int _tick = 0;
  int _surgeUntil = 0;
  bool _hovered = false;

  bool get _surging => _tick < _surgeUntil;

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
            final width = _extent(
              constraints.maxWidth,
              fallback: 126,
              maximum: 196,
            );
            final height = _extent(
              constraints.maxHeight,
              fallback: 50,
              maximum: 82,
            );
            final frame = _CityFramePainter(
              width: width,
              height: height,
              tick: _tick,
              hovered: _hovered,
              surging: _surging,
            ).paint();

            return Container(
              color: _CityPalette.background,
              child: RichText(
                text: frame.toTextSpan(),
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            );
          },
        ),
      ),
    );
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

class _CityFramePainter {
  _CityFramePainter({
    required this.width,
    required this.height,
    required this.tick,
    required this.hovered,
    required this.surging,
  }) : canvas = _CityCanvas(width, height);

  final int width;
  final int height;
  final int tick;
  final bool hovered;
  final bool surging;
  final _CityCanvas canvas;

  final List<_Point> _powerNodes = <_Point>[];
  final List<List<_Point>> _cables = <List<_Point>>[];
  final List<List<_Point>> _roads = <List<_Point>>[];

  _CityCanvas paint() {
    if (width < 44 || height < 20) {
      _compactScene();
      return canvas;
    }

    _starField();
    _hud();
    _backSkyline();
    _backRoadRing();
    _middleSkyline();
    _middleRoadRing();
    _frontSkyline();
    final core = _centralPlatform();
    _powerNetwork(core);
    _cableArcs();
    _plasma(core);
    _roadTraffic();
    _ambientParticles(core);
    _drone();

    return canvas;
  }

  void _compactScene() {
    final center = width ~/ 2;
    final bottom = height - 2;
    final top = math.max(1, height ~/ 5).toInt();

    for (var y = bottom - 5; y >= top; y--) {
      final sway = (math.sin(y * 0.82 + tick * 0.3) * 2).round();
      final radius = y > bottom - 10 ? 3 : y > bottom - 16 ? 2 : 1;
      for (var x = center + sway - radius; x <= center + sway + radius; x++) {
        final distance = (x - center - sway).abs();
        canvas.set(
          x,
          y,
          distance == 0 ? '#' : distance == 1 ? '*' : '·',
          distance == 0
              ? _Tone.white
              : distance == 1
                  ? _Tone.glow
                  : _Tone.pink,
        );
      }
    }

    canvas.write(center - 9, bottom - 3, '╭────────────────╮', _Tone.violet);
    canvas.write(center - 9, bottom - 2, '│     CINDER     │', _Tone.orange);
    canvas.write(center - 9, bottom - 1, '╰────────────────╯', _Tone.violet);
  }

  void _starField() {
    final drift = tick ~/ 9;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = _noise(x, y, drift);
        if (value % 389 == 0) {
          canvas.set(x, y, value.isEven ? '·' : '.', _Tone.star);
        } else if (value % 997 == 0) {
          canvas.set(x, y, tick.isEven ? '+' : '×', _Tone.pink);
        }
      }
    }
  }

  void _hud() {
    if (width < 98 || height < 38) return;
    _panel(2, 2, 12, 5, 'STATE', <String>['CORE', 'LIVE']);
    _panel(width - 14, 2, 12, 5, 'DIFF', <String>['MIN', 'LIVE']);
    _panel(2, height - 7, 15, 5, 'EVENTS', <String>['PULSE', 'ARC']);
    _panel(width - 17, height - 7, 15, 5, 'FRAME', <String>['ACTIVE', 'SYNC']);
  }

  void _panel(
    int x,
    int y,
    int panelWidth,
    int panelHeight,
    String title,
    List<String> values,
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
    for (var index = 0; index < values.length; index++) {
      canvas.write(x + 2, y + 2 + index, values[index], _Tone.violet);
    }
  }

  void _backSkyline() {
    final base = math.max(20, (height * 0.43).round()).toInt();
    _powerNodes.add(_building(width * 10 ~/ 100, base, 5, 8, 2, 11, _Tone.depth));
    _powerNodes.add(_building(width * 22 ~/ 100, base - 2, 6, 12, 3, 17, _Tone.violetDim));
    _powerNodes.add(_building(width * 35 ~/ 100, base, 5, 9, 2, 19, _Tone.depth));
    _powerNodes.add(_building(width * 65 ~/ 100, base, 5, 9, 2, 23, _Tone.depth));
    _powerNodes.add(_building(width * 78 ~/ 100, base - 2, 6, 12, 3, 29, _Tone.violetDim));
    _powerNodes.add(_building(width * 90 ~/ 100, base, 5, 8, 2, 31, _Tone.depth));
  }

  void _middleSkyline() {
    final base = math.max(30, (height * 0.65).round()).toInt();
    _powerNodes.add(_building(width * 7 ~/ 100, base, 7, 13, 3, 37, _Tone.violetDim));
    _powerNodes.add(_building(width * 21 ~/ 100, base - 1, 8, 12, 3, 41, _Tone.violet));
    _powerNodes.add(_building(width * 34 ~/ 100, base + 1, 7, 10, 3, 43, _Tone.violetDim));
    _powerNodes.add(_building(width * 66 ~/ 100, base + 1, 7, 10, 3, 47, _Tone.violetDim));
    _powerNodes.add(_building(width * 79 ~/ 100, base - 1, 8, 12, 3, 53, _Tone.violet));
    _powerNodes.add(_building(width * 93 ~/ 100, base, 7, 13, 3, 59, _Tone.violetDim));
  }

  void _frontSkyline() {
    final base = height - 3;
    _powerNodes.add(_building(width * 13 ~/ 100, base, 10, 16, 4, 61, _Tone.violet));
    _powerNodes.add(_building(width * 31 ~/ 100, base - 1, 10, 12, 4, 67, _Tone.violet));
    _powerNodes.add(_building(width * 69 ~/ 100, base - 1, 10, 12, 4, 71, _Tone.violet));
    _powerNodes.add(_building(width * 87 ~/ 100, base, 10, 16, 4, 73, _Tone.violet));
  }

  _Point _building(
    int centerX,
    int baseY,
    int halfWidth,
    int bodyHeight,
    int roofDepth,
    int seed,
    int wallTone,
  ) {
    final topY = baseY - bodyHeight;
    final roofBack = _Point(centerX, topY - roofDepth);
    final roofLeft = _Point(centerX - halfWidth, topY);
    final roofFront = _Point(centerX, topY + roofDepth);
    final roofRight = _Point(centerX + halfWidth, topY);
    final baseLeft = _Point(roofLeft.x, roofLeft.y + bodyHeight);
    final baseFront = _Point(roofFront.x, roofFront.y + bodyHeight);
    final baseRight = _Point(roofRight.x, roofRight.y + bodyHeight);

    _stroke(
      _polyline(<_Point>[
        roofBack,
        roofRight,
        roofFront,
        roofLeft,
        roofBack,
      ]),
      _Tone.violet,
    );
    _stroke(_line(roofLeft, baseLeft), wallTone);
    _stroke(_line(roofFront, baseFront), _Tone.violet);
    _stroke(_line(roofRight, baseRight), wallTone);
    _stroke(_line(baseLeft, baseFront), _Tone.depth);
    _stroke(_line(baseFront, baseRight), _Tone.depth);

    final floorCount = math.max(2, bodyHeight ~/ 3).toInt();
    for (var floor = 1; floor < floorCount; floor++) {
      final t = floor / floorCount;
      final leftEdge = _lerp(roofLeft, baseLeft, t);
      final frontEdge = _lerp(roofFront, baseFront, t);
      final rightEdge = _lerp(roofRight, baseRight, t);
      final leftFloor = _line(leftEdge, frontEdge);
      final rightFloor = _line(frontEdge, rightEdge);
      _stroke(leftFloor, _Tone.depth);
      _stroke(rightFloor, wallTone);
      _windows(leftFloor, seed + floor * 13);
      _windows(rightFloor, seed + floor * 17);
    }

    _facadeColumn(
      roofLeft,
      roofFront,
      baseLeft,
      baseFront,
      0.38,
      wallTone,
    );
    _facadeColumn(
      roofLeft,
      roofFront,
      baseLeft,
      baseFront,
      0.68,
      wallTone,
    );
    _facadeColumn(
      roofFront,
      roofRight,
      baseFront,
      baseRight,
      0.32,
      wallTone,
    );
    _facadeColumn(
      roofFront,
      roofRight,
      baseFront,
      baseRight,
      0.62,
      wallTone,
    );

    canvas.set(centerX, topY, '◆', _Tone.pink);
    final antennaHeight = 2 + seed % 4;
    canvas.vLine(
      centerX,
      topY - antennaHeight,
      topY - 1,
      '│',
      _Tone.violetDim,
    );
    canvas.set(
      centerX,
      topY - antennaHeight - 1,
      (tick + seed) % 9 < 2 ? '*' : '^',
      (tick + seed) % 9 < 2 ? _Tone.white : _Tone.violet,
    );

    if (halfWidth >= 8) {
      _roofUnit(centerX - halfWidth ~/ 3, topY, 3, seed);
      _roofUnit(centerX + halfWidth ~/ 3, topY, 2, seed + 5);
    }

    return _Point(centerX, topY - antennaHeight - 1);
  }

  void _roofUnit(int centerX, int baseY, int unitHeight, int seed) {
    final halfWidth = 2;
    final topY = baseY - unitHeight;
    canvas.set(centerX - halfWidth, topY, '╭', _Tone.violetDim);
    canvas.hLine(
      centerX - halfWidth + 1,
      centerX + halfWidth - 1,
      topY,
      '─',
      _Tone.violetDim,
    );
    canvas.set(centerX + halfWidth, topY, '╮', _Tone.violetDim);
    canvas.vLine(centerX - halfWidth, topY + 1, baseY - 1, '│', _Tone.depth);
    canvas.vLine(centerX + halfWidth, topY + 1, baseY - 1, '│', _Tone.violetDim);
    canvas.set(centerX, topY, seed.isEven ? '·' : '◆', _Tone.pink);
  }

  void _facadeColumn(
    _Point roofA,
    _Point roofB,
    _Point baseA,
    _Point baseB,
    double fraction,
    int tone,
  ) {
    final top = _lerp(roofA, roofB, fraction);
    final bottom = _lerp(baseA, baseB, fraction);
    _stroke(_line(top, bottom), tone, sparse: true, phase: (fraction * 10).round());
  }

  void _windows(List<_Point> edge, int seed) {
    for (var index = 2; index < edge.length - 1; index += 3) {
      final point = edge[index];
      final value = _noise(point.x, point.y, seed + tick ~/ 11);
      if (value % 5 == 0) continue;
      canvas.set(
        point.x,
        point.y,
        value % 7 == 0 ? '▥' : '·',
        value % 4 == 0 ? _Tone.orange : _Tone.pink,
      );
    }
  }

  void _backRoadRing() {
    final y = math.max(17, (height * 0.44).round()).toInt();
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

  void _middleRoadRing() {
    final y = math.max(27, (height * 0.69).round()).toInt();
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

  _Point _centralPlatform() {
    final centerX = width ~/ 2;
    final baseY = height - 8;
    const halfWidth = 15;
    const bodyHeight = 8;
    const roofDepth = 5;
    final topY = baseY - bodyHeight;
    final roofBack = _Point(centerX, topY - roofDepth);
    final roofLeft = _Point(centerX - halfWidth, topY);
    final roofFront = _Point(centerX, topY + roofDepth);
    final roofRight = _Point(centerX + halfWidth, topY);
    final baseLeft = _Point(roofLeft.x, roofLeft.y + bodyHeight);
    final baseFront = _Point(roofFront.x, roofFront.y + bodyHeight);
    final baseRight = _Point(roofRight.x, roofRight.y + bodyHeight);

    _stroke(
      _polyline(<_Point>[
        roofBack,
        roofRight,
        roofFront,
        roofLeft,
        roofBack,
      ]),
      _Tone.violet,
    );
    _stroke(_line(roofLeft, baseLeft), _Tone.violetDim);
    _stroke(_line(roofFront, baseFront), _Tone.violet);
    _stroke(_line(roofRight, baseRight), _Tone.violetDim);
    _stroke(_line(baseLeft, baseFront), _Tone.orangeDim);
    _stroke(_line(baseFront, baseRight), _Tone.orangeDim);

    final lowerFloorLeft = _lerp(roofLeft, baseLeft, 0.55);
    final lowerFloorFront = _lerp(roofFront, baseFront, 0.55);
    final lowerFloorRight = _lerp(roofRight, baseRight, 0.55);
    _stroke(_line(lowerFloorLeft, lowerFloorFront), _Tone.depth);
    _stroke(_line(lowerFloorFront, lowerFloorRight), _Tone.violetDim);

    canvas.write(centerX - 3, roofFront.y + 3, 'CINDER', _Tone.white);
    canvas.set(centerX, roofBack.y + 2, '◆', _Tone.white);

    for (var ring = 0; ring < 3; ring++) {
      final inset = ring * 3;
      final path = _polyline(<_Point>[
        _Point(roofLeft.x - inset, roofLeft.y + ring),
        _Point(roofBack.x, roofBack.y - ring),
        _Point(roofRight.x + inset, roofRight.y + ring),
      ]);
      _stroke(
        path,
        ring.isEven ? _Tone.orangeDim : _Tone.violetDim,
        sparse: true,
        phase: tick ~/ 4 + ring,
      );
    }

    return _Point(centerX, roofBack.y + 1);
  }

  void _powerNetwork(_Point core) {
    if (_powerNodes.isEmpty) return;
    final selected = <_Point>[];
    final stride = math.max(1, _powerNodes.length ~/ 7).toInt();
    for (var index = 0; index < _powerNodes.length; index += stride) {
      selected.add(_powerNodes[index]);
    }

    for (var index = 0; index < selected.length; index++) {
      final node = selected[index];
      final side = node.x < core.x ? -1 : 1;
      final bend = _Point(
        core.x + side * (10 + index % 3 * 4),
        math.min(core.y - 4, node.y + 4 + index % 3).toInt(),
      );
      final cable = _polyline(<_Point>[
        node,
        _Point(node.x, node.y + 2),
        bend,
        _Point(core.x + side * 3, core.y - 2),
        core,
      ]);
      _cables.add(cable);
      _stroke(cable, _Tone.violetDim, sparse: true, phase: index);

      final speed = surging ? 5 : 2;
      final pulse = _positiveMod(tick * speed + index * 17, cable.length);
      _movingPulse(cable, pulse, radius: surging ? 5 : 3, hot: index.isEven);
      if (hovered || surging) {
        _movingPulse(
          cable,
          _positiveMod(pulse + cable.length ~/ 2, cable.length),
          radius: 2,
          hot: !index.isEven,
        );
      }
    }
  }

  void _cableArcs() {
    if (_cables.length < 2) return;
    final count = surging
        ? math.min(6, _cables.length - 1).toInt()
        : math.min(2, _cables.length - 1).toInt();

    for (var index = 0; index < count; index++) {
      if (!surging && (tick + index * 5) % 19 > 4) continue;
      final first = _cables[index];
      final second = _cables[index + 1];
      final start = first[_positiveMod(tick * 2 + index * 7, first.length)];
      final end = second[
        _positiveMod(second.length - 1 - tick * 2 - index * 9, second.length)
      ];
      if ((start.x - end.x).abs() > math.max(20, width ~/ 5).toInt()) {
        continue;
      }
      if ((start.y - end.y).abs() > math.max(9, height ~/ 4).toInt()) {
        continue;
      }
      _electricArc(start, end, index * 101 + tick ~/ 2);
    }
  }

  void _electricArc(_Point start, _Point end, int seed) {
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
      final point = path[index];
      canvas.set(
        point.x,
        point.y,
        index % 3 == 0
            ? '*'
            : index.isEven
                ? '╱'
                : '╲',
        index % 3 == 0 ? _Tone.white : _Tone.glow,
      );
      if (surging && index % 4 == 0) {
        canvas.set(point.x - 1, point.y, '·', _Tone.pink);
        canvas.set(point.x + 1, point.y, '·', _Tone.pink);
      }
    }
  }

  void _plasma(_Point core) {
    final top = math.max(2, height ~/ 13).toInt();
    final bottom = core.y - 1;
    final amplitude = surging ? 1.5 : hovered ? 1.2 : 1;

    for (var y = bottom; y >= top; y--) {
      final progress = (bottom - y) / math.max(1, bottom - top);
      final wave = math.sin(y * 0.74 + tick * 0.31) * 2.1;
      final turbulence = (_noise(core.x, y, tick ~/ 2) % 7) - 3;
      final center = core.x + ((wave + turbulence * 0.4) * amplitude).round();
      final radius = math.max(
        1,
        2 +
            ((1 - progress) * math.max(2, width ~/ 48)).round() +
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

    final ringCount = surging ? 4 : 2;
    for (var ring = 0; ring < ringCount; ring++) {
      final radius = 4 +
          _positiveMod(tick + ring * 7, math.max(5, width ~/ 12).toInt());
      for (var dx = -radius; dx <= radius; dx++) {
        final dy = (radius - dx.abs()) ~/ 3;
        if (_noise(dx, dy, tick + ring) % 4 != 0) continue;
        final tone = ring.isEven ? _Tone.pink : _Tone.orange;
        canvas.set(core.x + dx, core.y + dy, '·', tone);
        canvas.set(core.x + dx, core.y - dy, '·', tone);
      }
    }
  }

  void _roadTraffic() {
    for (var roadIndex = 0; roadIndex < _roads.length; roadIndex++) {
      final road = _roads[roadIndex];
      if (road.isEmpty) continue;
      final vehicleCount = math.max(2, width ~/ 48).toInt();
      for (var vehicle = 0; vehicle < vehicleCount; vehicle++) {
        final offset = _positiveMod(
          tick * (2 + roadIndex % 3) +
              vehicle * math.max(8, road.length ~/ vehicleCount).toInt(),
          road.length,
        );
        final head = road[offset];
        final tail = road[_positiveMod(offset - 1, road.length)];
        canvas.set(head.x, head.y, roadIndex.isEven ? '>' : '<', _Tone.white);
        canvas.set(tail.x, tail.y, '─', _Tone.orange);
      }
    }
  }

  void _ambientParticles(_Point core) {
    final count = math.max(10, width * height ~/ 680).toInt();
    for (var index = 0; index < count; index++) {
      final seed = _noise(index, tick ~/ 2, 131);
      final x = _positiveMod(seed * 13 + tick * (index.isEven ? 1 : -1), width);
      final y = _positiveMod(seed * 7 - tick + index * 11, height);
      if ((x - core.x).abs() > width ~/ 3 || y > core.y + 8) continue;
      canvas.set(
        x,
        y,
        seed.isEven ? '·' : '+',
        seed % 3 == 0 ? _Tone.glow : _Tone.pink,
      );
    }
  }

  void _drone() {
    if (width < 78 || height < 28) return;
    final span = math.max(12, width - 38).toInt();
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 19 + travel : 19 + (span * 2 - travel);
    final y = math.max(
      6,
      height ~/ 3 + (math.sin(tick * 0.13) * 2).round(),
    ).toInt();
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

  _Point _lerp(_Point first, _Point second, double t) {
    return _Point(
      (first.x + (second.x - first.x) * t).round(),
      (first.y + (second.y - first.y) * t).round(),
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

class _CityCanvas {
  _CityCanvas(this.width, this.height)
      : _rows = List<List<_CityCell>>.generate(
          height,
          (_) => List<_CityCell>.generate(
            width,
            (_) => const _CityCell(' ', _Tone.empty),
            growable: false,
          ),
          growable: false,
        );

  final int width;
  final int height;
  final List<List<_CityCell>> _rows;

  void set(int x, int y, String glyph, int tone) {
    if (x < 0 || x >= width || y < 0 || y >= height || glyph.isEmpty) return;
    if (tone < _rows[y][x].tone) return;
    _rows[y][x] = _CityCell(glyph, tone);
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
            style: _CityPalette.styleFor(activeTone),
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

class _CityCell {
  const _CityCell(this.glyph, this.tone);

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

abstract class _CityPalette {
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
