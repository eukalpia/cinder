import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// A responsive isometric cyber-city rendered entirely by Cinder.
///
/// The browser provides only the terminal surface. Buildings, roads, power
/// cables, moving current, plasma, traffic, particles, hover state, keyboard
/// input, and resize behavior are all painted into Cinder terminal cells.
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
  int _phaseShift = 0;
  double _energy = 1;
  bool _paused = false;
  bool _hovered = false;

  bool get _surging => _tick < _surgeUntil;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 58), (_) {
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
          onTap: _triggerSurge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = _safeExtent(
                constraints.maxWidth,
                fallback: 160,
                maximum: 240,
              );
              final height = _safeExtent(
                constraints.maxHeight,
                fallback: 62,
                maximum: 104,
              );

              final world = _ElectricCityPainter(
                width: width,
                height: height,
                tick: _tick + _phaseShift,
                energy: _energy,
                surging: _surging,
                hovered: _hovered,
              ).paint();

              return Container(
                color: _Palette.voidBlack,
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
      _triggerSurge();
    } else if (key == LogicalKey.arrowUp) {
      setState(() => _energy = math.min(1.75, _energy + 0.12));
    } else if (key == LogicalKey.arrowDown) {
      setState(() => _energy = math.max(0.55, _energy - 0.12));
    } else if (key == LogicalKey.arrowLeft) {
      setState(() => _phaseShift -= 5);
    } else if (key == LogicalKey.arrowRight) {
      setState(() => _phaseShift += 5);
    } else if (key == LogicalKey.keyR) {
      setState(() {
        _tick = 0;
        _surgeUntil = 0;
        _phaseShift = 0;
        _energy = 1;
        _paused = false;
      });
    } else {
      return false;
    }

    return true;
  }

  void _triggerSurge() {
    setState(() {
      _surgeUntil = _tick + 34;
      _energy = math.min(1.75, _energy + 0.08);
    });
  }

  int _safeExtent(
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

class _ElectricCityPainter {
  _ElectricCityPainter({
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

  final List<List<_Point>> _powerCables = <List<_Point>>[];
  final List<List<_Point>> _roadLanes = <List<_Point>>[];
  final List<_Point> _roofNodes = <_Point>[];

  late final _Scene scene;

  _WorldCanvas paint() {
    if (width < 34 || height < 16) {
      _drawTinyWorld();
      return canvas;
    }

    scene = _Scene.fromViewport(width, height);

    _drawSparseSky();
    _drawDistantSkyline();
    _drawGroundPlane();
    _drawRoadNetwork();
    _drawIsometricDistricts();

    final core = _drawCentralPlatform();

    _drawPowerCables(core);
    _drawCableArcs();
    _drawRoadTraffic();
    _drawCorePlasma(core);
    _drawCoreAura(core);
    _drawAmbientLife(core);
    _drawDrone();

    return canvas;
  }

  void _drawTinyWorld() {
    final centerX = width ~/ 2;
    final platformY = height - 4;
    final flameTop = math.max(1, height ~/ 4).toInt();

    canvas.write(centerX - 8, platformY, '╱═══ >_ ═══╲', _Tone.violet);
    canvas.write(centerX - 5, platformY + 1, ' CINDER ', _Tone.orange);

    for (var y = platformY - 1; y >= flameTop; y--) {
      final progress = (platformY - y) / math.max(1, platformY - flameTop);
      final radius = math.max(0, (2.4 * (1 - progress)).round()).toInt();
      final drift = (math.sin(y * 0.8 + tick * 0.35) * 1.2).round();
      for (var x = centerX + drift - radius;
          x <= centerX + drift + radius;
          x++) {
        final distance = (x - centerX - drift).abs();
        canvas.set(
          x,
          y,
          distance == 0 ? '*' : '+',
          distance == 0 ? _Tone.white : _Tone.glow,
        );
      }
    }
  }

  void _drawSparseSky() {
    final drift = tick ~/ 10;

    for (var y = 0; y < scene.horizonY - 2; y++) {
      for (var x = 0; x < width; x++) {
        final hash = _noise(x, y, drift);
        if (hash % 433 == 0) {
          canvas.set(x, y, hash.isEven ? '·' : '.', _Tone.star);
        } else if (hash % 947 == 0) {
          canvas.set(
            x,
            y,
            (tick + x + y) % 8 < 2 ? '*' : '·',
            _Tone.violetDim,
          );
        }
      }
    }
  }

  void _drawDistantSkyline() {
    if (width < 70 || height < 28) return;

    final count = width < 120 ? 7 : 11;
    final spacing = math.max(9, width ~/ count).toInt();
    final baseY = scene.horizonY - 4;

    for (var index = 0; index < count; index++) {
      final center = spacing ~/ 2 + index * spacing;
      final seed = _noise(center, baseY, 19);
      final towerWidth = 5 + seed % math.max(3, spacing - 5).toInt();
      final towerHeight = 5 + seed % math.max(6, height ~/ 5).toInt();
      final left = center - towerWidth ~/ 2;
      final right = center + towerWidth ~/ 2;
      final top = math.max(2, baseY - towerHeight).toInt();

      canvas.set(left, top + 2, '╭', _Tone.depth);
      canvas.hLine(left + 1, right - 1, top + 2, '─', _Tone.depth);
      canvas.set(right, top + 2, '╮', _Tone.depth);
      canvas.vLine(left, top + 3, baseY, '│', _Tone.depth);
      canvas.vLine(right, top + 3, baseY, '│', _Tone.depth);

      final crownWidth = math.max(2, towerWidth - 4).toInt();
      final crownLeft = center - crownWidth ~/ 2;
      final crownRight = center + crownWidth ~/ 2;
      canvas.set(crownLeft, top, '╱', _Tone.violetDim);
      canvas.hLine(crownLeft + 1, crownRight - 1, top, '─', _Tone.violetDim);
      canvas.set(crownRight, top, '╲', _Tone.violetDim);
      canvas.vLine(center, math.max(0, top - 4).toInt(), top - 1, '│', _Tone.depth);

      for (var y = top + 4; y < baseY; y += 3) {
        for (var x = left + 2; x < right; x += 3) {
          final hash = _noise(x, y, seed + tick ~/ 12);
          if (hash % 4 != 0) {
            canvas.set(
              x,
              y,
              '·',
              hash % 11 == 0 ? _Tone.orangeDim : _Tone.depth,
            );
          }
        }
      }
    }
  }

  void _drawGroundPlane() {
    final radius = scene.radius.floor();

    for (var grid = -radius; grid <= radius; grid++) {
      final xPath = _sampleLogicalLine(
        x1: grid.toDouble(),
        y1: -scene.radius,
        x2: grid.toDouble(),
        y2: scene.radius,
        z: 0,
      );
      final yPath = _sampleLogicalLine(
        x1: -scene.radius,
        y1: grid.toDouble(),
        x2: scene.radius,
        y2: grid.toDouble(),
        z: 0,
      );

      _strokePath(
        xPath,
        grid.isEven ? _Tone.depth : _Tone.shadow,
        sparse: true,
        phase: grid.abs(),
      );
      _strokePath(
        yPath,
        grid.isEven ? _Tone.depth : _Tone.shadow,
        sparse: true,
        phase: grid.abs() + 3,
      );
    }

    final boundary = <_Point>[
      _iso(-scene.radius, -scene.radius, 0),
      _iso(scene.radius, -scene.radius, 0),
      _iso(scene.radius, scene.radius, 0),
      _iso(-scene.radius, scene.radius, 0),
    ];
    _drawPolygonEdges(boundary, _Tone.violetDim);
  }

  void _drawRoadNetwork() {
    final r = scene.radius + 0.2;
    final laneOffset = width < 70 ? 0.5 : 0.72;
    final roadOffsets = <double>[-laneOffset, laneOffset];

    for (final offset in roadOffsets) {
      final xRoad = _sampleLogicalLine(
        x1: -r,
        y1: offset,
        x2: r,
        y2: offset,
        z: 0.28,
      );
      final yRoad = _sampleLogicalLine(
        x1: offset,
        y1: -r,
        x2: offset,
        y2: r,
        z: 0.28,
      );

      _strokePath(xRoad, _Tone.violet, phase: offset.isNegative ? 2 : 5);
      _strokePath(yRoad, _Tone.violet, phase: offset.isNegative ? 7 : 1);
    }

    final xCenter = _sampleLogicalLine(
      x1: -r,
      y1: 0,
      x2: r,
      y2: 0,
      z: 0.42,
    );
    final yCenter = _sampleLogicalLine(
      x1: 0,
      y1: -r,
      x2: 0,
      y2: r,
      z: 0.42,
    );

    _roadLanes
      ..add(xCenter)
      ..add(yCenter);

    _strokeDashed(xCenter, _Tone.orange, dash: 5, gap: 3, phase: tick ~/ 3);
    _strokeDashed(yCenter, _Tone.orange, dash: 5, gap: 3, phase: tick ~/ 3 + 4);

    for (var ring = 2.1; ring <= scene.radius - 0.8; ring += 1.65) {
      final diamond = <_Point>[
        _iso(-ring, 0, 0.34),
        _iso(0, -ring, 0.34),
        _iso(ring, 0, 0.34),
        _iso(0, ring, 0.34),
      ];
      _drawPolygonEdges(
        diamond,
        ((ring * 10).round() + tick ~/ 5).isEven
            ? _Tone.orangeDim
            : _Tone.violetDim,
      );
    }
  }

  void _drawIsometricDistricts() {
    final buildings = _buildingPlan()
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));

    for (final building in buildings) {
      final visible = building.x.abs() <= scene.radius + 0.7 &&
          building.y.abs() <= scene.radius + 0.7;
      if (!visible) continue;

      final roofNode = _drawBuilding(building);
      if (building.cabled && roofNode != null) _roofNodes.add(roofNode);
    }
  }

  List<_CityBuilding> _buildingPlan() {
    final all = <_CityBuilding>[
      const _CityBuilding(-4.5, -4.2, 1.7, 1.5, 14, 11, true),
      const _CityBuilding(-2.3, -4.7, 1.8, 1.5, 18, 13, false),
      const _CityBuilding(1.7, -4.7, 1.7, 1.6, 20, 17, true),
      const _CityBuilding(3.9, -4.1, 1.8, 1.6, 16, 19, false),
      const _CityBuilding(4.5, -2.0, 1.6, 1.8, 22, 23, true),
      const _CityBuilding(4.6, 1.8, 1.7, 1.8, 17, 29, false),
      const _CityBuilding(3.8, 3.8, 1.9, 1.7, 23, 31, true),
      const _CityBuilding(1.7, 4.5, 1.7, 1.7, 18, 37, false),
      const _CityBuilding(-2.2, 4.5, 1.9, 1.6, 24, 41, true),
      const _CityBuilding(-4.2, 3.7, 1.8, 1.8, 19, 43, false),
      const _CityBuilding(-4.7, 1.6, 1.6, 1.9, 22, 47, true),
      const _CityBuilding(-4.6, -2.0, 1.8, 1.6, 17, 53, false),
      const _CityBuilding(-2.35, -2.35, 1.35, 1.35, 13, 59, true),
      const _CityBuilding(1.15, -2.45, 1.45, 1.35, 15, 61, false),
      const _CityBuilding(1.2, 1.25, 1.4, 1.45, 16, 67, true),
      const _CityBuilding(-2.45, 1.2, 1.35, 1.45, 14, 71, false),
    ];

    if (width < 62) {
      return <_CityBuilding>[
        all[12],
        all[13],
        all[14],
        all[15],
        all[1],
        all[6],
      ];
    }

    if (width < 105) {
      return <_CityBuilding>[
        ...all.sublist(0, 4),
        ...all.sublist(6, 10),
        ...all.sublist(12),
      ];
    }

    if (height < 42) {
      return all.where((building) => building.height <= 20).toList();
    }

    return all;
  }

  _Point? _drawBuilding(_CityBuilding building) {
    final baseCenter = _iso(
      building.x + building.w / 2,
      building.y + building.d / 2,
      0,
    );
    if (baseCenter.x < -24 ||
        baseCenter.x > width + 24 ||
        baseCenter.y < -12 ||
        baseCenter.y > height + 10) {
      return null;
    }

    final baseY = _iso(building.x + building.w, building.y + building.d, 0).y;
    final maxHeight = math.max(5, baseY - 2).toInt();
    final heightRows = math.min(
      maxHeight,
      (building.height * scene.heightScale).round(),
    ).toInt();
    if (heightRows < 4) return null;

    final top = <_Point>[
      _iso(building.x, building.y, heightRows.toDouble()),
      _iso(building.x + building.w, building.y, heightRows.toDouble()),
      _iso(
        building.x + building.w,
        building.y + building.d,
        heightRows.toDouble(),
      ),
      _iso(building.x, building.y + building.d, heightRows.toDouble()),
    ];
    final base = <_Point>[
      _iso(building.x, building.y, 0),
      _iso(building.x + building.w, building.y, 0),
      _iso(building.x + building.w, building.y + building.d, 0),
      _iso(building.x, building.y + building.d, 0),
    ];

    final rightFace = <_Point>[top[1], top[2], base[2], base[1]];
    final leftFace = <_Point>[top[2], top[3], base[3], base[2]];

    _fillPolygon(
      rightFace,
      glyphs: const <String>[' ', '·', ':', ' '],
      tone: _Tone.shadow,
      seed: building.seed,
      density: 3,
    );
    _fillPolygon(
      leftFace,
      glyphs: const <String>[' ', '·', ' ', ':'],
      tone: _Tone.depth,
      seed: building.seed + 7,
      density: 3,
    );
    _fillPolygon(
      top,
      glyphs: const <String>['░', '·', '░', ' '],
      tone: _Tone.violetDim,
      seed: building.seed + 13,
      density: 4,
    );

    _drawPolygonEdges(rightFace, _Tone.violetDim);
    _drawPolygonEdges(leftFace, _Tone.violet);
    _drawPolygonEdges(top, _Tone.violet);

    _drawFacadeWindows(building, heightRows);
    _drawRoofDetails(building, heightRows);

    final roofCenter = _iso(
      building.x + building.w / 2,
      building.y + building.d / 2,
      heightRows.toDouble(),
    );
    final antennaHeight = 2 + building.seed % 5;
    canvas.vLine(
      roofCenter.x,
      roofCenter.y - antennaHeight,
      roofCenter.y - 1,
      '│',
      _Tone.violetDim,
    );
    final tip = _Point(roofCenter.x, roofCenter.y - antennaHeight - 1);
    canvas.set(
      tip.x,
      tip.y,
      (tick + building.seed) % 14 < 3 ? '*' : '·',
      building.cabled ? _Tone.pink : _Tone.violet,
    );

    return tip;
  }

  void _drawFacadeWindows(_CityBuilding building, int buildingHeight) {
    final rowStep = buildingHeight < 10 ? 3 : 2;

    for (var z = 2; z < buildingHeight - 2; z += rowStep) {
      for (var index = 1; index <= 4; index++) {
        final t = index / 5;

        final right = _iso(
          building.x + building.w,
          building.y + building.d * t,
          z.toDouble(),
        );
        final left = _iso(
          building.x + building.w * t,
          building.y + building.d,
          z.toDouble(),
        );

        final rightHash = _noise(right.x, right.y, building.seed + tick ~/ 9);
        final leftHash = _noise(left.x, left.y, building.seed + 31 + tick ~/ 11);

        if (rightHash % 5 != 0) {
          canvas.set(
            right.x,
            right.y,
            rightHash % 9 == 0 ? '▪' : '·',
            _windowTone(rightHash),
          );
        }
        if (leftHash % 5 != 0) {
          canvas.set(
            left.x,
            left.y,
            leftHash % 8 == 0 ? '▪' : '·',
            _windowTone(leftHash),
          );
        }
      }
    }
  }

  int _windowTone(int hash) {
    return switch (hash % 12) {
      0 || 1 => _Tone.glow,
      2 || 3 => _Tone.orange,
      4 => _Tone.pink,
      _ => _Tone.violetDim,
    };
  }

  void _drawRoofDetails(_CityBuilding building, int buildingHeight) {
    if (building.w < 1.5 || building.d < 1.4) return;

    final inset = 0.34;
    final z = buildingHeight + 1.0;
    final tier = <_Point>[
      _iso(building.x + inset, building.y + inset, z),
      _iso(building.x + building.w - inset, building.y + inset, z),
      _iso(
        building.x + building.w - inset,
        building.y + building.d - inset,
        z,
      ),
      _iso(building.x + inset, building.y + building.d - inset, z),
    ];

    _fillPolygon(
      tier,
      glyphs: const <String>['░', ' ', '·'],
      tone: _Tone.violetDim,
      seed: building.seed + 89,
      density: 4,
    );
    _drawPolygonEdges(tier, _Tone.violet);
  }

  _Point _drawCentralPlatform() {
    const radius = 1.65;
    const deckZ = 1.1;

    final deck = <_Point>[
      _iso(-radius, -radius, deckZ),
      _iso(radius, -radius, deckZ),
      _iso(radius, radius, deckZ),
      _iso(-radius, radius, deckZ),
    ];
    final base = <_Point>[
      _iso(-radius, -radius, 0),
      _iso(radius, -radius, 0),
      _iso(radius, radius, 0),
      _iso(-radius, radius, 0),
    ];

    _fillPolygon(
      <_Point>[deck[1], deck[2], base[2], base[1]],
      glyphs: const <String>[' ', ':', '·'],
      tone: _Tone.shadow,
      seed: 131,
      density: 3,
    );
    _fillPolygon(
      <_Point>[deck[2], deck[3], base[3], base[2]],
      glyphs: const <String>[' ', '·', ':'],
      tone: _Tone.depth,
      seed: 137,
      density: 3,
    );
    _fillPolygon(
      deck,
      glyphs: const <String>['░', '·', ' ', '░'],
      tone: _Tone.violetDim,
      seed: 149 + tick ~/ 8,
      density: 4,
    );

    _drawPolygonEdges(<_Point>[deck[1], deck[2], base[2], base[1]], _Tone.violet);
    _drawPolygonEdges(<_Point>[deck[2], deck[3], base[3], base[2]], _Tone.violet);
    _drawPolygonEdges(deck, _Tone.pink);

    final center = _iso(0, 0, deckZ);
    final labelY = math.min(height - 2, center.y + 3).toInt();
    canvas.write(center.x - 4, labelY, '>_ CINDER', _Tone.white);

    final socket = _iso(0, 0, 5.2);
    canvas.write(socket.x - 3, socket.y + 1, '╲╱╲╱╲', _Tone.orange);
    canvas.set(socket.x, socket.y, '◆', _Tone.white);

    return socket;
  }

  void _drawPowerCables(_Point socket) {
    if (_roofNodes.isEmpty) return;

    final maximum = width < 72 ? 4 : width < 120 ? 6 : 8;
    final candidates = <_Point>[];

    for (var i = 0; i < _roofNodes.length; i++) {
      if (candidates.length >= maximum) break;
      final node = _roofNodes[i];
      if ((node.x - socket.x).abs() < 8) continue;
      candidates.add(node);
    }

    candidates.sort((a, b) => a.x.compareTo(b.x));

    for (var index = 0; index < candidates.length; index++) {
      final start = candidates[index];
      final path = _saggingCable(start, socket, index);
      _powerCables.add(path);
      _strokePath(
        path,
        index.isEven ? _Tone.violet : _Tone.violetDim,
        sparse: false,
      );

      final speed = surging ? 5 : 2 + (energy * 1.2).round();
      final pulse = _positiveMod(tick * speed + index * 23, path.length);
      _drawPulse(
        path,
        pulse,
        radius: surging ? 5 : 3,
        hot: index.isEven,
      );

      if (hovered || surging) {
        final second = _positiveMod(pulse + path.length ~/ 2, path.length);
        _drawPulse(path, second, radius: 2, hot: !index.isEven);
      }
    }
  }

  List<_Point> _saggingCable(_Point start, _Point end, int seed) {
    final path = <_Point>[];
    final distance = (start.x - end.x).abs();
    final steps = math.max(16, distance + (start.y - end.y).abs()).toInt();
    final sag = 2.0 + distance / 24 + seed % 3;

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final x = _lerp(start.x, end.x, t).round();
      final baseY = _lerp(start.y, end.y, t);
      final y = (baseY + math.sin(math.pi * t) * sag).round();
      final point = _Point(x, y);
      if (path.isEmpty || path.last != point) path.add(point);
    }

    return path;
  }

  void _drawCableArcs() {
    if (_powerCables.length < 2) return;

    final arcLimit = surging ? 4 : hovered ? 2 : 1;

    for (var index = 0; index < arcLimit; index++) {
      if (!surging && (tick + index * 7) % 31 > 4) continue;

      final first = _powerCables[index % _powerCables.length];
      final second = _powerCables[(index + 1) % _powerCables.length];
      final firstIndex = ((first.length - 1) * (0.42 + index * 0.07)).round();
      final secondIndex = ((second.length - 1) * (0.52 - index * 0.04)).round();
      final start = first[firstIndex.clamp(0, first.length - 1).toInt()];
      final end = second[secondIndex.clamp(0, second.length - 1).toInt()];

      if ((start.x - end.x).abs() > width ~/ 4 ||
          (start.y - end.y).abs() > height ~/ 4) {
        continue;
      }

      _drawJaggedArc(start, end, seed: tick + index * 97);
    }
  }

  void _drawJaggedArc(_Point start, _Point end, {required int seed}) {
    final controls = <_Point>[start];
    final segments = math.max(4, math.min(10, (start.x - end.x).abs() ~/ 4 + 4))
        .toInt();

    for (var index = 1; index < segments; index++) {
      final t = index / segments;
      final x = _lerp(start.x, end.x, t).round();
      final y = _lerp(start.y, end.y, t).round();
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
      if (surging && index % 5 == 0) {
        canvas.set(point.x - 1, point.y, '·', _Tone.pink);
        canvas.set(point.x + 1, point.y, '·', _Tone.pink);
      }
    }
  }

  void _drawRoadTraffic() {
    for (var laneIndex = 0; laneIndex < _roadLanes.length; laneIndex++) {
      final lane = _roadLanes[laneIndex];
      if (lane.isEmpty) continue;

      final vehicleCount = width < 70 ? 2 : width < 130 ? 4 : 6;
      for (var vehicle = 0; vehicle < vehicleCount; vehicle++) {
        final offset = _positiveMod(
          tick * (1 + laneIndex) +
              vehicle * math.max(8, lane.length ~/ vehicleCount).toInt(),
          lane.length,
        );
        final point = lane[offset];
        final previous = lane[_positiveMod(offset - 1, lane.length)];
        final next = lane[_positiveMod(offset + 1, lane.length)];
        final glyph = _pathGlyph(previous, next);

        canvas.set(point.x, point.y, '◆', _Tone.white);
        canvas.set(previous.x, previous.y, glyph, _Tone.orange);
        if (surging) canvas.set(next.x, next.y, '·', _Tone.glow);
      }
    }
  }

  void _drawCorePlasma(_Point socket) {
    final plumeHeight = math.max(
      9,
      math.min(24, (height * 0.29 * energy).round()),
    ).toInt();
    final topY = math.max(1, socket.y - plumeHeight).toInt();

    for (var y = socket.y - 1; y >= topY; y--) {
      final progress = (socket.y - y) / math.max(1, socket.y - topY);
      final envelope = math.sin(math.pi * math.min(1, progress * 0.92));
      final baseRadius = (1.4 + envelope * 3.8 * energy).round();
      final taper = progress > 0.72
          ? ((1 - progress) / 0.28).clamp(0, 1).toDouble()
          : 1.0;
      final radius = math.max(1, (baseRadius * taper).round()).toInt();
      final turbulence = math.sin(y * 0.78 + tick * 0.31) +
          math.sin(y * 0.31 - tick * 0.19) * 0.6;
      final drift = (turbulence * (surging ? 2.1 : 1.3)).round();
      final center = socket.x + drift;

      for (var x = center - radius - 2; x <= center + radius + 2; x++) {
        final distance = (x - center).abs();
        final heat = _noise(x, y, tick * 3 + y);

        if (distance > radius && heat % 6 != 0) continue;

        if (distance == 0 || (distance <= 1 && heat % 4 != 0)) {
          canvas.set(
            x,
            y,
            heat.isEven ? '█' : '#',
            _Tone.white,
          );
        } else if (distance <= math.max(1, radius ~/ 2).toInt()) {
          canvas.set(
            x,
            y,
            const <String>['▓', '#', '*'][heat % 3],
            _Tone.glow,
          );
        } else if (distance <= radius) {
          canvas.set(
            x,
            y,
            const <String>['▒', '*', '+'][heat % 3],
            _Tone.orange,
          );
        } else {
          canvas.set(
            x,
            y,
            heat.isEven ? '·' : ':',
            _Tone.pink,
          );
        }
      }
    }

    for (var particle = 0; particle < (surging ? 18 : 9); particle++) {
      final seed = _noise(particle, tick ~/ 2, 211);
      final y = topY + _positiveMod(seed - tick * (1 + particle % 2), plumeHeight);
      final spread = math.max(3, ((socket.y - y) * 0.35).round()).toInt();
      final x = socket.x + (seed % (spread * 2 + 1)) - spread;
      canvas.set(
        x,
        y,
        particle % 4 == 0 ? '*' : '·',
        particle % 3 == 0 ? _Tone.white : _Tone.pink,
      );
    }
  }

  void _drawCoreAura(_Point socket) {
    final ringCount = surging ? 4 : hovered ? 3 : 2;
    final maximumRadius = math.max(5, math.min(width ~/ 8, height ~/ 4)).toInt();

    for (var ring = 0; ring < ringCount; ring++) {
      final radius = 4 + _positiveMod(tick ~/ 2 + ring * 7, maximumRadius);
      for (var dx = -radius; dx <= radius; dx++) {
        if ((dx + ring + tick) % 3 != 0) continue;
        final dy = math.max(1, (radius - dx.abs()) ~/ 3).toInt();
        final tone = ring.isEven ? _Tone.pink : _Tone.orangeDim;
        canvas.set(socket.x + dx, socket.y + dy + 2, '·', tone);
        canvas.set(socket.x + dx, socket.y - dy + 2, '·', tone);
      }
    }
  }

  void _drawAmbientLife(_Point socket) {
    final count = math.max(8, width * height ~/ 850).toInt();

    for (var index = 0; index < count; index++) {
      final seed = _noise(index, tick ~/ 2, 251);
      final x = _positiveMod(seed * 13 + tick * (index.isEven ? 1 : -1), width);
      final y = _positiveMod(seed * 7 - tick + index * 17, height);
      final distanceFromCore = (x - socket.x).abs() + (y - socket.y).abs();
      if (distanceFromCore < 10) continue;

      final phase = _positiveMod(tick + index * 5, 17);
      if (phase < 2) {
        canvas.set(x, y, '*', _Tone.white);
      } else if (phase < 6) {
        canvas.set(x, y, '·', _Tone.pink);
      } else {
        canvas.set(x, y, '.', _Tone.orangeDim);
      }
    }
  }

  void _drawDrone() {
    if (width < 86 || height < 30) return;

    final span = math.max(18, width - 42).toInt();
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 20 + travel : 20 + span * 2 - travel;
    final y = math.max(
      4,
      scene.horizonY - 12 + (math.sin(tick * 0.13) * 2).round(),
    ).toInt();
    final facingRight = travel < span;

    canvas.write(x - 2, y, facingRight ? '─[>]' : '[<]─', _Tone.white);
    canvas.set(facingRight ? x - 3 : x + 3, y, '·', _Tone.orange);
  }

  List<_Point> _sampleLogicalLine({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double z,
  }) {
    final distance = math.max((x2 - x1).abs(), (y2 - y1).abs());
    final steps = math.max(8, (distance * scene.tileX * 1.4).round()).toInt();
    final points = <_Point>[];

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final point = _iso(
        _lerp(x1, x2, t),
        _lerp(y1, y2, t),
        z,
      );
      if (points.isEmpty || points.last != point) points.add(point);
    }

    return points;
  }

  _Point _iso(double x, double y, double z) {
    return _Point(
      scene.centerX + ((x - y) * scene.tileX).round(),
      scene.horizonY + ((x + y) * scene.tileY).round() - z.round(),
    );
  }

  void _fillPolygon(
    List<_Point> polygon, {
    required List<String> glyphs,
    required int tone,
    required int seed,
    required int density,
  }) {
    if (polygon.length < 3) return;

    var minX = polygon.first.x;
    var maxX = polygon.first.x;
    var minY = polygon.first.y;
    var maxY = polygon.first.y;

    for (final point in polygon.skip(1)) {
      minX = math.min(minX, point.x).toInt();
      maxX = math.max(maxX, point.x).toInt();
      minY = math.min(minY, point.y).toInt();
      maxY = math.max(maxY, point.y).toInt();
    }

    minX = minX.clamp(0, width - 1).toInt();
    maxX = maxX.clamp(0, width - 1).toInt();
    minY = minY.clamp(0, height - 1).toInt();
    maxY = maxY.clamp(0, height - 1).toInt();

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (!_pointInsidePolygon(x + 0.5, y + 0.5, polygon)) continue;
        final hash = _noise(x, y, seed);
        if (hash % density == 0) continue;
        final glyph = glyphs[hash % glyphs.length];
        if (glyph == ' ') continue;
        canvas.set(x, y, glyph, tone);
      }
    }
  }

  bool _pointInsidePolygon(double x, double y, List<_Point> polygon) {
    var inside = false;

    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x.toDouble();
      final yi = polygon[i].y.toDouble();
      final xj = polygon[j].x.toDouble();
      final yj = polygon[j].y.toDouble();

      final intersects = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) /
                  ((yj - yi).abs() < 0.0001 ? 0.0001 : yj - yi) +
              xi);
      if (intersects) inside = !inside;
    }

    return inside;
  }

  void _drawPolygonEdges(List<_Point> polygon, int tone) {
    if (polygon.length < 2) return;

    for (var index = 0; index < polygon.length; index++) {
      final start = polygon[index];
      final end = polygon[(index + 1) % polygon.length];
      _strokePath(_line(start, end), tone);
    }
  }

  void _strokeDashed(
    List<_Point> path,
    int tone, {
    required int dash,
    required int gap,
    required int phase,
  }) {
    final period = math.max(1, dash + gap).toInt();

    for (var index = 0; index < path.length; index++) {
      if (_positiveMod(index + phase, period) >= dash) continue;
      final previous = index > 0 ? path[index - 1] : path[index];
      final next = index < path.length - 1 ? path[index + 1] : path[index];
      canvas.set(path[index].x, path[index].y, _pathGlyph(previous, next), tone);
    }
  }

  void _strokePath(
    List<_Point> path,
    int tone, {
    bool sparse = false,
    int phase = 0,
  }) {
    for (var index = 0; index < path.length; index++) {
      if (sparse && (index + phase) % 5 == 0) continue;
      final previous = index > 0 ? path[index - 1] : path[index];
      final next = index < path.length - 1 ? path[index + 1] : path[index];
      canvas.set(path[index].x, path[index].y, _pathGlyph(previous, next), tone);
    }
  }

  void _drawPulse(
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
        canvas.set(point.x, point.y, '◆', _Tone.white);
      } else if (distance == 1) {
        canvas.set(point.x, point.y, '*', _Tone.glow);
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

  String _pathGlyph(_Point previous, _Point next) {
    final dx = next.x - previous.x;
    final dy = next.y - previous.y;
    if (dx == 0) return '│';
    if (dy == 0) return '─';
    return dx.sign == dy.sign ? '╲' : '╱';
  }

  double _lerp(num start, num end, double t) {
    return (start + (end - start) * t).toDouble();
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

class _Scene {
  const _Scene({
    required this.centerX,
    required this.horizonY,
    required this.tileX,
    required this.tileY,
    required this.radius,
    required this.heightScale,
  });

  factory _Scene.fromViewport(int width, int height) {
    final compact = width < 72;
    final tileX = math.max(
      4,
      math.min(compact ? 5 : 9, width ~/ (compact ? 10 : 24)),
    ).toInt();
    final tileY = math.max(
      1,
      math.min(3, (height * 0.035).round()),
    ).toInt();
    final radius = width < 62
        ? 3.15
        : width < 105
            ? 4.45
            : 5.65;
    final horizon = math.max(
      12,
      math.min(height - 18, (height * (compact ? 0.44 : 0.49)).round()),
    ).toInt();

    return _Scene(
      centerX: width ~/ 2,
      horizonY: horizon,
      tileX: tileX,
      tileY: tileY,
      radius: radius,
      heightScale: height < 42 ? 0.68 : height < 62 ? 0.84 : 1,
    );
  }

  final int centerX;
  final int horizonY;
  final int tileX;
  final int tileY;
  final double radius;
  final double heightScale;
}

class _CityBuilding {
  const _CityBuilding(
    this.x,
    this.y,
    this.w,
    this.d,
    this.height,
    this.seed,
    this.cabled,
  );

  final double x;
  final double y;
  final double w;
  final double d;
  final int height;
  final int seed;
  final bool cabled;
}

class _WorldCanvas {
  _WorldCanvas(this.width, this.height)
      : _rows = List<List<_WorldCell>>.generate(
          height,
          (_) => List<_WorldCell>.generate(
            width,
            (_) => const _WorldCell(' ', _Tone.empty),
            growable: false,
          ),
          growable: false,
        );

  final int width;
  final int height;
  final List<List<_WorldCell>> _rows;

  void set(int x, int y, String glyph, int tone) {
    if (x < 0 || x >= width || y < 0 || y >= height || glyph.isEmpty) return;
    _rows[y][x] = _WorldCell(glyph, tone);
  }

  void write(int x, int y, String text, int tone) {
    final glyphs = text.runes.map(String.fromCharCode).toList(growable: false);
    for (var index = 0; index < glyphs.length; index++) {
      set(x + index, y, glyphs[index], tone);
    }
  }

  void hLine(
    int startX,
    int endX,
    int y,
    String glyph,
    int tone,
  ) {
    final left = math.min(startX, endX).toInt();
    final right = math.max(startX, endX).toInt();
    for (var x = left; x <= right; x++) {
      set(x, y, glyph, tone);
    }
  }

  void vLine(
    int x,
    int startY,
    int endY,
    String glyph,
    int tone,
  ) {
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

class _WorldCell {
  const _WorldCell(this.glyph, this.tone);

  final String glyph;
  final int tone;
}

class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _Point && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}

abstract class _Tone {
  static const int empty = 0;
  static const int star = 1;
  static const int shadow = 2;
  static const int depth = 3;
  static const int violetDim = 4;
  static const int orangeDim = 5;
  static const int violet = 6;
  static const int orange = 7;
  static const int pink = 8;
  static const int glow = 9;
  static const int white = 10;
}

abstract class _Palette {
  static const Color voidBlack = Color.fromRGB(2, 3, 8);
  static const Color star = Color.fromRGB(44, 29, 62);
  static const Color shadow = Color.fromRGB(35, 24, 53);
  static const Color depth = Color.fromRGB(58, 35, 83);
  static const Color violetDim = Color.fromRGB(105, 55, 151);
  static const Color orangeDim = Color.fromRGB(140, 65, 20);
  static const Color violet = Color.fromRGB(190, 84, 246);
  static const Color orange = Color.fromRGB(232, 105, 27);
  static const Color pink = Color.fromRGB(255, 62, 184);
  static const Color glow = Color.fromRGB(255, 174, 56);
  static const Color white = Color.fromRGB(255, 241, 224);

  static TextStyle? styleFor(int tone) {
    return switch (tone) {
      _Tone.star => const TextStyle(color: star, fontWeight: FontWeight.dim),
      _Tone.shadow =>
        const TextStyle(color: shadow, fontWeight: FontWeight.dim),
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
