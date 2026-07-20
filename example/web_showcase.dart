import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// A living terminal city rendered entirely by Cinder.
///
/// The browser only provides the terminal surface. Buildings, roads, cables,
/// plasma, electricity, hover state, keyboard input, and animation are all
/// produced by Cinder widgets and terminal cells.
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
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
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
              final width = _safeExtent(constraints.maxWidth, fallback: 150);
              final height = _safeExtent(constraints.maxHeight, fallback: 52);
              final frame = _ElectricCityPainter(
                width: width,
                height: height,
                tick: _tick + _phaseShift,
                energy: _energy,
                surging: _surging,
                hovered: _hovered,
              ).paint();

              return Container(
                color: _Palette.voidBlack,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _layer(frame.stars, _Palette.star, FontWeight.dim),
                    _layer(frame.depth, _Palette.depth, FontWeight.dim),
                    _layer(frame.structure, _Palette.violetDim, FontWeight.dim),
                    _layer(
                        frame.violet, _Palette.violetBright, FontWeight.bold),
                    _layer(frame.orange, _Palette.orange, FontWeight.bold),
                    _layer(frame.pink, _Palette.pink, FontWeight.bold),
                    _layer(frame.glow, _Palette.orangeBright, FontWeight.bold),
                    _layer(frame.white, _Palette.white, FontWeight.bold),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _layer(String value, Color color, FontWeight weight) {
    return Positioned.fill(
      child: Text(
        value,
        softWrap: false,
        style: TextStyle(color: color, fontWeight: weight),
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
      setState(() => _energy = math.min(1.7, _energy + 0.12));
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
      _energy = math.min(1.7, _energy + 0.08);
    });
  }

  int _safeExtent(double value, {required int fallback}) {
    if (!value.isFinite || value <= 0) return fallback;
    return value.floor().clamp(1, 500).toInt();
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
  });

  final int width;
  final int height;
  final int tick;
  final double energy;
  final bool surging;
  final bool hovered;

  late final _GlyphCanvas _stars = _GlyphCanvas(width, height);
  late final _GlyphCanvas _depth = _GlyphCanvas(width, height);
  late final _GlyphCanvas _structure = _GlyphCanvas(width, height);
  late final _GlyphCanvas _violet = _GlyphCanvas(width, height);
  late final _GlyphCanvas _orange = _GlyphCanvas(width, height);
  late final _GlyphCanvas _pink = _GlyphCanvas(width, height);
  late final _GlyphCanvas _glow = _GlyphCanvas(width, height);
  late final _GlyphCanvas _white = _GlyphCanvas(width, height);

  final List<_Point> _towerTips = <_Point>[];
  final List<List<_Point>> _cables = <List<_Point>>[];

  _WorldFrame paint() {
    if (width < 34 || height < 14) {
      _drawTinyWorld();
      return _buildFrame();
    }

    _drawStars();
    _drawAtmosphere();
    _drawDistantCity();
    _drawMidCity();
    _drawRoadNetwork();
    _drawForegroundCity();
    final socket = _drawCoreDistrict();
    _drawCableNetwork(socket);
    _drawPlasmaColumn(socket);
    _drawElectricityBetweenCables();
    _drawTraffic();
    _drawAmbientSparks();
    _drawDrone();

    return _buildFrame();
  }

  _WorldFrame _buildFrame() {
    return _WorldFrame(
      stars: _stars.build(),
      depth: _depth.build(),
      structure: _structure.build(),
      violet: _violet.build(),
      orange: _orange.build(),
      pink: _pink.build(),
      glow: _glow.build(),
      white: _white.build(),
    );
  }

  void _drawTinyWorld() {
    final centerX = width ~/ 2;
    final baseY = height - 2;
    final topY = math.max(1, height ~/ 4);

    for (var y = topY; y < baseY - 3; y++) {
      final pulse = _noise(centerX, y, tick ~/ 2);
      final half = 1 + pulse % 2;
      for (var x = centerX - half; x <= centerX + half; x++) {
        final heat = _noise(x, y, tick);
        if (heat % 4 == 0) {
          _pink.set(x, y, ':');
        } else if (x == centerX) {
          _white.set(x, y, heat.isEven ? '#' : '*');
        } else {
          _glow.set(x, y, heat.isEven ? '+' : '*');
        }
      }
    }

    _violet.write(centerX - 7, baseY - 3, '╭────────────╮');
    _violet.write(centerX - 7, baseY - 2, '│   CINDER   │');
    _violet.write(centerX - 7, baseY - 1, '╰────────────╯');
  }

  void _drawStars() {
    final drift = tick ~/ 5;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hash = _noise(x, y, drift);
        if (hash % 173 == 0) {
          _stars.set(x, y, hash.isEven ? '·' : '.');
        } else if (hash % 433 == 0) {
          _stars.set(x, y, tick.isEven ? '+' : '×');
        } else if (hash % 617 == 0) {
          _stars.set(x, y, '^');
        }
      }
    }
  }

  void _drawAtmosphere() {
    final centerX = width ~/ 2;
    final top = math.max(2, height ~/ 14);
    final bottom = math.max(top + 1, (height * 0.62).round());

    for (var y = top; y < bottom; y++) {
      final progress = (y - top) / math.max(1, bottom - top);
      final radius = math.max(3, (progress * width * 0.22).round());
      for (var x = centerX - radius; x <= centerX + radius; x++) {
        final distance = (x - centerX).abs();
        final hash = _noise(x, y, tick ~/ 3);
        final threshold = 8 + (progress * 16).round();
        if (distance < radius && hash % 97 < threshold) {
          final glyph = hash % 5 == 0 ? ':' : '·';
          if (distance < radius ~/ 3) {
            _pink.set(x, y, glyph);
          } else {
            _depth.set(x, y, glyph);
          }
        }
      }
    }
  }

  void _drawDistantCity() {
    final baseY = math.max(10, (height * 0.47).round());
    final spacing = width < 90 ? 12 : 15;
    var index = 0;

    for (var x = 3; x < width - 3; x += spacing) {
      final seed = _noise(x, baseY, 11);
      final buildingWidth = 7 + seed % math.max(3, spacing - 5).toInt();
      final buildingHeight = 7 + seed % math.max(6, height ~/ 4).toInt();
      final center = math.min(width - 4, x + buildingWidth ~/ 2).toInt();
      _drawTower(
        centerX: center,
        baseY: baseY + seed % 3,
        towerWidth: buildingWidth,
        towerHeight: buildingHeight,
        seed: seed + index,
        canvas: _depth,
        foreground: false,
      );
      index++;
    }
  }

  void _drawMidCity() {
    final baseY = math.max(14, (height * 0.66).round());
    final spacing = width < 100 ? 16 : 20;
    var index = 0;

    for (var x = -2; x < width + 4; x += spacing) {
      final seed = _noise(x + 19, baseY, 29);
      final buildingWidth = 10 + seed % 7;
      final buildingHeight = 10 + seed % math.max(8, height ~/ 3).toInt();
      final center = x + buildingWidth ~/ 2;
      final tip = _drawTower(
        centerX: center,
        baseY: baseY + seed % 4,
        towerWidth: buildingWidth,
        towerHeight: buildingHeight,
        seed: seed + index * 7,
        canvas: _structure,
        foreground: true,
      );
      if (tip.x > 2 && tip.x < width - 2) _towerTips.add(tip);
      index++;
    }
  }

  void _drawForegroundCity() {
    final baseY = height - 1;
    final centerX = width ~/ 2;
    final exclusion = math.max(18, width ~/ 7).toInt();
    final spacing = width < 110 ? 18 : 23;

    for (var x = -4; x < width + 4; x += spacing) {
      final center = x + spacing ~/ 2;
      if ((center - centerX).abs() < exclusion) continue;
      final seed = _noise(center, baseY, 47);
      final towerWidth = 12 + seed % 9;
      final towerHeight = 11 + seed % math.max(8, height ~/ 3).toInt();
      final tip = _drawTower(
        centerX: center,
        baseY: baseY,
        towerWidth: towerWidth,
        towerHeight: towerHeight,
        seed: seed,
        canvas: _violet,
        foreground: true,
      );
      if (tip.x > 2 && tip.x < width - 2) _towerTips.add(tip);
    }
  }

  _Point _drawTower({
    required int centerX,
    required int baseY,
    required int towerWidth,
    required int towerHeight,
    required int seed,
    required _GlyphCanvas canvas,
    required bool foreground,
  }) {
    final availableHeight = math.max(5, math.min(towerHeight, baseY - 2));
    final levels = availableHeight < 12 ? 2 : 3;
    var currentBottom = baseY;
    var currentWidth = math.max(6, towerWidth);

    for (var level = 0; level < levels; level++) {
      final remainingLevels = levels - level;
      final levelHeight = math.max(
        3,
        (availableHeight / levels).round() + ((_noise(seed, level, 3) % 3) - 1),
      );
      final left = centerX - currentWidth ~/ 2;
      final right = left + currentWidth - 1;
      final top = math.max(2, currentBottom - levelHeight);

      canvas.set(left, top, '╭');
      canvas.hLine(left + 1, right - 1, top, '─');
      canvas.set(right, top, '╮');
      canvas.vLine(left, top + 1, currentBottom - 1, '│');
      canvas.vLine(right, top + 1, currentBottom - 1, '│');
      canvas.set(left, currentBottom, '╰');
      canvas.hLine(left + 1, right - 1, currentBottom, '─');
      canvas.set(right, currentBottom, '╯');

      if (currentWidth >= 8) {
        canvas.set(left + 1, top - 1, '╱');
        canvas.hLine(left + 2, right - 2, top - 1, '─');
        canvas.set(right - 1, top - 1, '╲');
      }

      _drawWindows(
        left: left,
        right: right,
        top: top,
        bottom: currentBottom,
        seed: seed + level * 31,
        foreground: foreground,
      );

      currentBottom = top - 1;
      currentWidth = math.max(5, currentWidth - 2 - seed % 2);
      if (remainingLevels == 1) break;
    }

    final antennaBottom = math.max(2, currentBottom);
    final antennaHeight = 2 + seed % 5;
    for (var y = antennaBottom - antennaHeight; y < antennaBottom; y++) {
      canvas.set(centerX, y, '│');
    }
    canvas.set(
        centerX, antennaBottom - antennaHeight - 1, seed.isEven ? '^' : '·');

    if (foreground) {
      final pulseY = antennaBottom - antennaHeight - 1;
      final pulse = (tick + seed) % 8;
      if (pulse < 2) {
        _pink.set(centerX - 1, pulseY, '·');
        _white.set(centerX, pulseY, '*');
        _pink.set(centerX + 1, pulseY, '·');
      }
    }

    return _Point(centerX, antennaBottom - antennaHeight - 1);
  }

  void _drawWindows({
    required int left,
    required int right,
    required int top,
    required int bottom,
    required int seed,
    required bool foreground,
  }) {
    if (right - left < 5 || bottom - top < 3) return;

    for (var y = top + 2; y < bottom; y += 2) {
      for (var x = left + 2; x < right - 1; x += 3) {
        final hash = _noise(x, y, seed + tick ~/ 7);
        if (hash % 5 == 0) continue;
        final glyph = foreground && hash % 7 == 0 ? '▥' : '·';
        if (hash % 4 == 0) {
          _orange.set(x, y, glyph);
        } else if (hash % 3 == 0) {
          _pink.set(x, y, glyph);
        } else {
          _violet.set(x, y, glyph);
        }
      }
    }
  }

  void _drawRoadNetwork() {
    final centerX = width ~/ 2;
    final horizonY = math.max(12, (height * 0.53).round());
    final lowerY = math.max(horizonY + 4, (height * 0.78).round());

    final roads = <List<_Point>>[
      <_Point>[
        _Point(0, lowerY),
        _Point(centerX - width ~/ 5, horizonY + 4),
        _Point(centerX - 7, horizonY),
      ],
      <_Point>[
        _Point(width - 1, lowerY),
        _Point(centerX + width ~/ 5, horizonY + 4),
        _Point(centerX + 7, horizonY),
      ],
      <_Point>[
        _Point(0, height - 5),
        _Point(centerX - width ~/ 4, lowerY),
        _Point(centerX - 10, horizonY + 3),
      ],
      <_Point>[
        _Point(width - 1, height - 5),
        _Point(centerX + width ~/ 4, lowerY),
        _Point(centerX + 10, horizonY + 3),
      ],
      <_Point>[
        _Point(math.max(0, width ~/ 10), horizonY + 1),
        _Point(centerX, horizonY + 6),
        _Point(math.min(width - 1, width - width ~/ 10), horizonY + 1),
      ],
    ];

    for (var index = 0; index < roads.length; index++) {
      final path = _polyline(roads[index]);
      _stroke(_structure, path, sparse: true, phase: index);
      final offset =
          _positiveMod(tick * 2 + index * 17, math.max(1, path.length));
      _drawMovingPulse(path, offset, radius: 3, hot: index.isEven);
      final second =
          _positiveMod(offset + path.length ~/ 2, math.max(1, path.length));
      _drawMovingPulse(path, second, radius: 2, hot: !index.isEven);
    }

    for (var ring = 0; ring < 3; ring++) {
      final y = horizonY + 6 + ring * 4;
      final inset = 7 + ring * math.max(5, width ~/ 16);
      final left = inset.clamp(1, width - 2).toInt();
      final right = (width - inset - 1).clamp(1, width - 2).toInt();
      if (left >= right) continue;
      for (var x = left; x <= right; x++) {
        if ((x + tick ~/ 2 + ring * 3) % 7 < 5) {
          _orange.set(x, y, '─');
        }
      }
      _violet.set(left, y, '╲');
      _violet.set(right, y, '╱');
    }
  }

  _Point _drawCoreDistrict() {
    final centerX = width ~/ 2;
    final baseY = height - 2;
    final districtWidth = math.max(20, math.min(48, width ~/ 3)).toInt();
    final left = centerX - districtWidth ~/ 2;
    final right = centerX + districtWidth ~/ 2;
    final roofY = math.max(12, (height * 0.64).round()).toInt();
    final shoulderY = math.min(baseY - 6, roofY + 5).toInt();

    _violet.set(left, shoulderY, '╭');
    _violet.hLine(left + 1, right - 1, shoulderY, '─');
    _violet.set(right, shoulderY, '╮');
    _violet.vLine(left, shoulderY + 1, baseY - 1, '│');
    _violet.vLine(right, shoulderY + 1, baseY - 1, '│');
    _violet.set(left, baseY, '╰');
    _violet.hLine(left + 1, right - 1, baseY, '─');
    _violet.set(right, baseY, '╯');

    final roofLeft = left - math.min(8, width ~/ 18).toInt();
    final roofRight = right + math.min(8, width ~/ 18).toInt();
    final roofPath = _polyline(<_Point>[
      _Point(roofLeft, shoulderY),
      _Point(left + 4, roofY),
      _Point(right - 4, roofY),
      _Point(roofRight, shoulderY),
    ]);
    _stroke(_violet, roofPath);

    final innerLeft = centerX - math.max(6, districtWidth ~/ 5).toInt();
    final innerRight = centerX + math.max(6, districtWidth ~/ 5).toInt();
    final socketY = math.max(7, roofY - 2).toInt();
    _orange.write(centerX - 4, roofY + 2, 'CINDER');

    for (var y = shoulderY + 2; y < baseY; y += 2) {
      for (var x = left + 3; x < right - 2; x += 4) {
        final hash = _noise(x, y, 73 + tick ~/ 8);
        if (hash % 3 == 0) {
          _orange.set(x, y, hash.isEven ? '·' : ':');
        } else {
          _violet.set(x, y, '·');
        }
      }
    }

    _violet.set(innerLeft, roofY, '╭');
    _violet.hLine(innerLeft + 1, innerRight - 1, roofY, '─');
    _violet.set(innerRight, roofY, '╮');
    _violet.vLine(innerLeft, socketY + 1, roofY - 1, '│');
    _violet.vLine(innerRight, socketY + 1, roofY - 1, '│');

    _glow.set(centerX - 2, socketY, '╲');
    _white.set(centerX, socketY, '*');
    _glow.set(centerX + 2, socketY, '╱');

    final platformY = math.min(baseY - 3, shoulderY + 3).toInt();
    final platformLeft = math.max(1, roofLeft - 8).toInt();
    final platformRight = math.min(width - 2, roofRight + 8).toInt();
    _structure.hLine(platformLeft, platformRight, platformY, '═');
    for (var x = platformLeft; x <= platformRight; x++) {
      if ((x + tick) % 9 == 0) _orange.set(x, platformY, '◆');
    }

    return _Point(centerX, socketY);
  }

  void _drawCableNetwork(_Point socket) {
    if (_towerTips.isEmpty) return;

    final selectedTips = <_Point>[];
    final stride = math
        .max(
          1,
          _towerTips.length ~/ math.max(4, width ~/ 28).toInt(),
        )
        .toInt();
    for (var i = 0; i < _towerTips.length; i += stride) {
      selectedTips.add(_towerTips[i]);
    }

    for (var i = 0; i < selectedTips.length; i++) {
      final tip = selectedTips[i];
      final side = tip.x < socket.x ? -1 : 1;
      final bendY = math
          .max(
            tip.y + 2,
            socket.y - 8 - (i % 4) * 2,
          )
          .toInt();
      final bendX = socket.x + side * (8 + (i % 3) * 5);
      final path = _polyline(<_Point>[
        tip,
        _Point(tip.x, math.min(height - 2, tip.y + 3 + i % 3)),
        _Point(bendX, bendY),
        _Point(socket.x + side * 3, socket.y - 2),
        socket,
      ]);
      if (path.length < 2) continue;
      _cables.add(path);
      _stroke(_violet, path, sparse: true, phase: i);
      _animateCable(path, i);
    }

    final crossLinks = <List<_Point>>[];
    for (var i = 1; i < selectedTips.length; i++) {
      final left = selectedTips[i - 1];
      final right = selectedTips[i];
      if ((right.x - left.x).abs() > width ~/ 3) continue;
      final y = math.max(left.y, right.y) + 2 + i % 3;
      crossLinks.add(_polyline(<_Point>[
        left,
        _Point(left.x, y),
        _Point(right.x, y),
        right,
      ]));
    }

    for (var i = 0; i < crossLinks.length; i++) {
      final path = crossLinks[i];
      _stroke(_structure, path, sparse: true, phase: i + 4);
      if ((tick + i * 7) % 19 < 10 || surging) {
        _drawMovingPulse(
          path,
          _positiveMod(tick * 3 + i * 13, math.max(1, path.length)),
          radius: surging ? 4 : 2,
          hot: i.isEven,
        );
      }
    }
  }

  void _animateCable(List<_Point> path, int seed) {
    final speed = surging ? 5 : 2 + (energy * 1.4).round();
    final offset = _positiveMod(tick * speed + seed * 19, path.length);
    _drawMovingPulse(path, offset, radius: surging ? 5 : 3, hot: seed.isEven);

    if (surging || hovered) {
      final second = _positiveMod(offset + path.length ~/ 3, path.length);
      _drawMovingPulse(path, second, radius: 2, hot: !seed.isEven);
    }
  }

  void _drawElectricityBetweenCables() {
    if (_cables.length < 2) return;
    final arcCount = surging
        ? math.min(8, _cables.length - 1)
        : math.min(3, _cables.length - 1);

    for (var i = 0; i < arcCount; i++) {
      final left = _cables[i];
      final right = _cables[i + 1];
      if (left.length < 4 || right.length < 4) continue;
      final phase = _positiveMod(tick * 2 + i * 11, 100) / 100;
      final leftIndex = (phase * (left.length - 1)).round();
      final rightIndex = ((1 - phase * 0.65) * (right.length - 1)).round();
      final start = left[leftIndex.clamp(0, left.length - 1).toInt()];
      final end = right[rightIndex.clamp(0, right.length - 1).toInt()];
      if ((start.x - end.x).abs() > math.max(22, width ~/ 4)) continue;
      if ((start.y - end.y).abs() > math.max(12, height ~/ 3)) continue;
      if (!surging && (tick + i * 5) % 17 > 5) continue;
      _drawJaggedArc(start, end, seed: i * 97 + tick ~/ 2);
    }
  }

  void _drawJaggedArc(_Point start, _Point end, {required int seed}) {
    final segments = math.max(3, math.min(9, (start.x - end.x).abs() ~/ 4 + 3));
    final controls = <_Point>[start];
    for (var i = 1; i < segments; i++) {
      final t = i / segments;
      final x = (start.x + (end.x - start.x) * t).round();
      final y = (start.y + (end.y - start.y) * t).round();
      final jitter = (_noise(x, y, seed + i) % 5) - 2;
      controls.add(_Point(x, y + jitter));
    }
    controls.add(end);
    final path = _polyline(controls);
    for (var i = 0; i < path.length; i++) {
      final point = path[i];
      if (i % 3 == 0) {
        _white.set(point.x, point.y, i.isEven ? '*' : '+');
      } else {
        _glow.set(point.x, point.y, i.isEven ? '/' : '\\');
      }
      if (surging && i % 4 == 0) {
        _pink.set(point.x - 1, point.y, '·');
        _pink.set(point.x + 1, point.y, '·');
      }
    }
  }

  void _drawPlasmaColumn(_Point socket) {
    final top = math.max(1, height ~/ 18);
    final bottom = math.max(top + 2, socket.y - 1);
    final centerX = socket.x;
    final amplitude = surging
        ? 1.55
        : hovered
            ? 1.2
            : 1;

    for (var y = bottom; y >= top; y--) {
      final progress = (bottom - y) / math.max(1, bottom - top);
      final plume = math.sin((y * 0.72) + tick * 0.28) * 2.2;
      final turbulence = (_noise(centerX, y, tick ~/ 2) % 7) - 3;
      final drift = ((plume + turbulence * 0.45) * amplitude).round();
      final baseRadius =
          2 + ((1 - progress) * math.max(2, width ~/ 36)).round();
      final breathe = ((_noise(y, tick, 83) % 3) - 1) + (surging ? 2 : 0);
      final radius = math.max(1, baseRadius + breathe);
      final rowCenter = centerX + drift;

      for (var x = rowCenter - radius - 2; x <= rowCenter + radius + 2; x++) {
        final distance = (x - rowCenter).abs();
        final heat = _noise(x, y, tick + y * 3);
        if (distance > radius && heat % 4 != 0) continue;

        if (distance == 0 || (distance <= 1 && heat % 3 != 0)) {
          _white.set(x, y, heat.isEven ? '#' : '*');
        } else if (distance <= math.max(1, radius ~/ 2)) {
          _glow.set(x, y, const <String>['#', '*', '+'][heat % 3]);
        } else if (distance <= radius) {
          _orange.set(x, y, const <String>['*', '+', ':'][heat % 3]);
        } else {
          _pink.set(x, y, heat.isEven ? '·' : ':');
        }
      }

      if ((y + tick) % 5 == 0) {
        _pink.set(rowCenter - radius - 3, y, '·');
        _pink.set(rowCenter + radius + 3, y, '·');
      }
    }

    final crownY = math.max(1, top - 1);
    _pink.set(centerX - 2, crownY + 1, '╲');
    _white.set(centerX, crownY, '*');
    _pink.set(centerX + 2, crownY + 1, '╱');
  }

  void _drawTraffic() {
    final horizonY = math.max(10, (height * 0.58).round());
    final tracks = <List<_Point>>[
      _polyline(<_Point>[
        _Point(0, horizonY + 2),
        _Point(width ~/ 3, horizonY + 6),
        _Point(width - 1, horizonY + 1),
      ]),
      _polyline(<_Point>[
        _Point(width - 1, height - 4),
        _Point(width * 2 ~/ 3, horizonY + 8),
        _Point(0, horizonY + 5),
      ]),
    ];

    for (var i = 0; i < tracks.length; i++) {
      final path = tracks[i];
      if (path.isEmpty) continue;
      for (var vehicle = 0; vehicle < math.max(2, width ~/ 45); vehicle++) {
        final offset = _positiveMod(
          tick * (2 + i) + vehicle * math.max(7, path.length ~/ 4),
          path.length,
        );
        final point = path[offset];
        _white.set(point.x, point.y, i.isEven ? '>' : '<');
        final tailIndex = _positiveMod(offset - 1 - i, path.length);
        final tail = path[tailIndex];
        _orange.set(tail.x, tail.y, '─');
      }
    }
  }

  void _drawAmbientSparks() {
    final count = math.max(12, width * height ~/ 330);
    for (var i = 0; i < count; i++) {
      final seed = _noise(i, tick ~/ 2, 101);
      final x = _positiveMod(seed * 17 + tick * (i.isEven ? 1 : -1), width);
      final y = _positiveMod(seed * 7 - tick + i * 11, height);
      final phase = _positiveMod(tick + i * 3, 9);
      if (phase < 2) {
        _white.set(x, y, phase == 0 ? '*' : '+');
      } else if (phase < 5) {
        _pink.set(x, y, '·');
      } else {
        _orange.set(x, y, '.');
      }
    }
  }

  void _drawDrone() {
    if (width < 70 || height < 24) return;
    final span = math.max(12, width - 32);
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 16 + travel : 16 + (span * 2 - travel);
    final y = math.max(5, height ~/ 3 + (math.sin(tick * 0.13) * 3).round());
    final facingRight = travel < span;
    _white.write(x - 2, y, facingRight ? '─[>]' : '[<]─');
    _orange.set(facingRight ? x - 3 : x + 3, y, '·');
  }

  void _drawMovingPulse(
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
        _white.set(point.x, point.y, '*');
      } else if (distance <= 1) {
        _glow.set(point.x, point.y, hot ? '#' : '+');
      } else if (hot) {
        _orange.set(point.x, point.y, distance.isEven ? ':' : '·');
      } else {
        _pink.set(point.x, point.y, distance.isEven ? ':' : '·');
      }
    }
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
    _GlyphCanvas canvas,
    List<_Point> path, {
    bool sparse = false,
    int phase = 0,
  }) {
    for (var i = 0; i < path.length; i++) {
      if (sparse && (i + phase + tick ~/ 4) % 6 == 0) continue;
      final previous = i > 0 ? path[i - 1] : path[i];
      final next = i < path.length - 1 ? path[i + 1] : path[i];
      canvas.set(path[i].x, path[i].y, _pathGlyph(previous, next));
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

class _GlyphCanvas {
  _GlyphCanvas(this.width, this.height)
      : _rows = List<List<String>>.generate(
          height,
          (_) => List<String>.filled(width, ' ', growable: false),
          growable: false,
        );

  final int width;
  final int height;
  final List<List<String>> _rows;

  void set(int x, int y, String glyph) {
    if (x < 0 || x >= width || y < 0 || y >= height || glyph.isEmpty) return;
    _rows[y][x] = glyph;
  }

  void write(int x, int y, String text) {
    for (var index = 0; index < text.length; index++) {
      set(x + index, y, text[index]);
    }
  }

  void hLine(int startX, int endX, int y, String glyph) {
    final left = math.min(startX, endX);
    final right = math.max(startX, endX);
    for (var x = left; x <= right; x++) {
      set(x, y, glyph);
    }
  }

  void vLine(int x, int startY, int endY, String glyph) {
    final top = math.min(startY, endY);
    final bottom = math.max(startY, endY);
    for (var y = top; y <= bottom; y++) {
      set(x, y, glyph);
    }
  }

  String build() {
    return _rows.map((row) {
      return row.join().replaceFirst(RegExp(r'\s+$'), '');
    }).join('\n');
  }
}

class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}

class _WorldFrame {
  const _WorldFrame({
    required this.stars,
    required this.depth,
    required this.structure,
    required this.violet,
    required this.orange,
    required this.pink,
    required this.glow,
    required this.white,
  });

  final String stars;
  final String depth;
  final String structure;
  final String violet;
  final String orange;
  final String pink;
  final String glow;
  final String white;
}

abstract class _Palette {
  static const Color voidBlack = Color.fromRGB(2, 3, 8);
  static const Color star = Color.fromRGB(75, 42, 96);
  static const Color depth = Color.fromRGB(50, 34, 73);
  static const Color violetDim = Color.fromRGB(91, 48, 132);
  static const Color violetBright = Color.fromRGB(190, 84, 246);
  static const Color pink = Color.fromRGB(255, 62, 184);
  static const Color orange = Color.fromRGB(232, 105, 27);
  static const Color orangeBright = Color.fromRGB(255, 174, 56);
  static const Color white = Color.fromRGB(255, 241, 224);
}
