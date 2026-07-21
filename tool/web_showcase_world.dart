import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// A living terminal metropolis rendered entirely by Cinder.
///
/// The browser only hosts a terminal surface. Every building, cable, electric
/// pulse, plasma particle, road, vehicle, hover response, and resize pass is
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
              final width = _safeExtent(
                constraints.maxWidth,
                fallback: 160,
                maximum: 280,
              );
              final height = _safeExtent(
                constraints.maxHeight,
                fallback: 56,
                maximum: 120,
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
      setState(() => _energy = math.min(1.8, _energy + 0.12));
    } else if (key == LogicalKey.arrowDown) {
      setState(() => _energy = math.max(0.5, _energy - 0.12));
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
      _surgeUntil = _tick + 38;
      _energy = math.min(1.8, _energy + 0.08);
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

  final List<_Point> _towerTips = <_Point>[];
  final List<List<_Point>> _cables = <List<_Point>>[];
  final List<List<_Point>> _roads = <List<_Point>>[];

  _WorldCanvas paint() {
    if (width < 34 || height < 14) {
      _drawTinyWorld();
      return canvas;
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
    _drawEnergyHalo(socket);

    return canvas;
  }

  void _drawTinyWorld() {
    final centerX = width ~/ 2;
    final baseY = height - 2;
    final topY = math.max(1, height ~/ 4).toInt();

    for (var y = topY; y < baseY - 3; y++) {
      final pulse = _noise(centerX, y, tick ~/ 2);
      final half = 1 + pulse % 2;
      for (var x = centerX - half; x <= centerX + half; x++) {
        final heat = _noise(x, y, tick);
        if (x == centerX) {
          canvas.set(x, y, heat.isEven ? '#' : '*', _Tone.white);
        } else if (heat % 3 == 0) {
          canvas.set(x, y, '+', _Tone.glow);
        } else {
          canvas.set(x, y, ':', _Tone.pink);
        }
      }
    }

    canvas.write(centerX - 7, baseY - 3, '╭────────────╮', _Tone.violet);
    canvas.write(centerX - 7, baseY - 2, '│   CINDER   │', _Tone.orange);
    canvas.write(centerX - 7, baseY - 1, '╰────────────╯', _Tone.violet);
  }

  void _drawStars() {
    final drift = tick ~/ 6;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hash = _noise(x, y, drift);
        if (hash % 157 == 0) {
          canvas.set(x, y, hash.isEven ? '·' : '.', _Tone.star);
        } else if (hash % 389 == 0) {
          canvas.set(x, y, tick.isEven ? '+' : '×', _Tone.pink);
        } else if (hash % 587 == 0) {
          canvas.set(x, y, '^', _Tone.violetDim);
        }
      }
    }
  }

  void _drawAtmosphere() {
    final centerX = width ~/ 2;
    final top = math.max(1, height ~/ 18).toInt();
    final bottom = math.max(top + 1, (height * 0.64).round()).toInt();

    for (var y = top; y < bottom; y++) {
      final progress = (y - top) / math.max(1, bottom - top);
      final radius = math.max(4, (progress * width * 0.24).round()).toInt();
      for (var x = centerX - radius; x <= centerX + radius; x++) {
        final distance = (x - centerX).abs();
        final hash = _noise(x, y, tick ~/ 3);
        final threshold = 7 + (progress * 18).round();
        if (distance >= radius || hash % 101 >= threshold) continue;
        if (distance < radius ~/ 3) {
          canvas.set(x, y, hash.isEven ? ':' : '·', _Tone.pink);
        } else {
          canvas.set(x, y, hash.isEven ? '·' : '.', _Tone.depth);
        }
      }
    }
  }

  void _drawDistantCity() {
    final baseY = math.max(10, (height * 0.47).round()).toInt();
    final spacing = width < 90 ? 12 : 15;
    var index = 0;

    for (var x = 2; x < width - 2; x += spacing) {
      final seed = _noise(x, baseY, 11);
      final buildingWidth = 7 + seed % math.max(3, spacing - 5).toInt();
      final buildingHeight =
          7 + seed % math.max(6, height ~/ 4).toInt();
      final center = math.min(width - 4, x + buildingWidth ~/ 2).toInt();
      _drawTower(
        centerX: center,
        baseY: baseY + seed % 3,
        towerWidth: buildingWidth,
        towerHeight: buildingHeight,
        seed: seed + index,
        tone: _Tone.depth,
        foreground: false,
      );
      index++;
    }
  }

  void _drawMidCity() {
    final baseY = math.max(14, (height * 0.67).round()).toInt();
    final spacing = width < 100 ? 16 : 20;
    var index = 0;

    for (var x = -2; x < width + 4; x += spacing) {
      final seed = _noise(x + 19, baseY, 29);
      final buildingWidth = 10 + seed % 7;
      final buildingHeight =
          10 + seed % math.max(8, height ~/ 3).toInt();
      final center = x + buildingWidth ~/ 2;
      final tip = _drawTower(
        centerX: center,
        baseY: baseY + seed % 4,
        towerWidth: buildingWidth,
        towerHeight: buildingHeight,
        seed: seed + index * 7,
        tone: _Tone.violetDim,
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
      final towerHeight =
          11 + seed % math.max(8, height ~/ 3).toInt();
      final tip = _drawTower(
        centerX: center,
        baseY: baseY,
        towerWidth: towerWidth,
        towerHeight: towerHeight,
        seed: seed,
        tone: _Tone.violet,
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
    required int tone,
    required bool foreground,
  }) {
    final availableHeight =
        math.max(5, math.min(towerHeight, baseY - 2)).toInt();
    final levels = availableHeight < 12 ? 2 : 3;
    var currentBottom = baseY;
    var currentWidth = math.max(6, towerWidth).toInt();

    for (var level = 0; level < levels; level++) {
      final levelHeight = math.max(
        3,
        (availableHeight / levels).round() +
            ((_noise(seed, level, 3) % 3) - 1),
      ).toInt();
      final left = centerX - currentWidth ~/ 2;
      final right = left + currentWidth - 1;
      final top = math.max(2, currentBottom - levelHeight).toInt();

      canvas.set(left, top, '╭', tone);
      canvas.hLine(left + 1, right - 1, top, '─', tone);
      canvas.set(right, top, '╮', tone);
      canvas.vLine(left, top + 1, currentBottom - 1, '│', tone);
      canvas.vLine(right, top + 1, currentBottom - 1, '│', tone);
      canvas.set(left, currentBottom, '╰', tone);
      canvas.hLine(left + 1, right - 1, currentBottom, '─', tone);
      canvas.set(right, currentBottom, '╯', tone);

      if (currentWidth >= 8) {
        canvas.set(left + 1, top - 1, '╱', tone);
        canvas.hLine(left + 2, right - 2, top - 1, '─', tone);
        canvas.set(right - 1, top - 1, '╲', tone);
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
      currentWidth = math.max(5, currentWidth - 2 - seed % 2).toInt();
    }

    final antennaBottom = math.max(2, currentBottom).toInt();
    final antennaHeight = 2 + seed % 5;
    for (var y = antennaBottom - antennaHeight; y < antennaBottom; y++) {
      canvas.set(centerX, y, '│', tone);
    }
    final tipY = antennaBottom - antennaHeight - 1;
    canvas.set(centerX, tipY, seed.isEven ? '^' : '·', tone);

    if (foreground && (tick + seed) % 8 < 2) {
      canvas.set(centerX - 1, tipY, '·', _Tone.pink);
      canvas.set(centerX, tipY, '*', _Tone.white);
      canvas.set(centerX + 1, tipY, '·', _Tone.pink);
    }

    return _Point(centerX, tipY);
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
        final tone = switch (hash % 7) {
          0 || 1 => _Tone.orange,
          2 => _Tone.pink,
          _ => _Tone.violet,
        };
        canvas.set(x, y, glyph, tone);
      }
    }
  }

  void _drawRoadNetwork() {
    final centerX = width ~/ 2;
    final horizonY = math.max(12, (height * 0.53).round()).toInt();
    final lowerY = math.max(horizonY + 4, (height * 0.79).round()).toInt();

    _roads.addAll(<List<_Point>>[
      _polyline(<_Point>[
        _Point(0, lowerY),
        _Point(centerX - width ~/ 5, horizonY + 4),
        _Point(centerX - 7, horizonY),
      ]),
      _polyline(<_Point>[
        _Point(width - 1, lowerY),
        _Point(centerX + width ~/ 5, horizonY + 4),
        _Point(centerX + 7, horizonY),
      ]),
      _polyline(<_Point>[
        _Point(0, height - 5),
        _Point(centerX - width ~/ 4, lowerY),
        _Point(centerX - 10, horizonY + 3),
      ]),
      _polyline(<_Point>[
        _Point(width - 1, height - 5),
        _Point(centerX + width ~/ 4, lowerY),
        _Point(centerX + 10, horizonY + 3),
      ]),
      _polyline(<_Point>[
        _Point(math.max(0, width ~/ 10).toInt(), horizonY + 1),
        _Point(centerX, horizonY + 6),
        _Point(math.min(width - 1, width - width ~/ 10).toInt(), horizonY + 1),
      ]),
    ]);

    for (var index = 0; index < _roads.length; index++) {
      final path = _roads[index];
      _stroke(path, _Tone.violetDim, sparse: true, phase: index);
      final offset = _positiveMod(
        tick * 2 + index * 17,
        math.max(1, path.length).toInt(),
      );
      _drawMovingPulse(
        path,
        offset,
        radius: 3,
        hot: index.isEven,
      );
      final second = _positiveMod(
        offset + path.length ~/ 2,
        math.max(1, path.length).toInt(),
      );
      _drawMovingPulse(
        path,
        second,
        radius: 2,
        hot: !index.isEven,
      );
    }

    for (var ring = 0; ring < 3; ring++) {
      final y = horizonY + 6 + ring * 4;
      final inset = 7 + ring * math.max(5, width ~/ 16).toInt();
      final left = inset.clamp(1, width - 2).toInt();
      final right = (width - inset - 1).clamp(1, width - 2).toInt();
      if (left >= right || y >= height) continue;
      for (var x = left; x <= right; x++) {
        if ((x + tick ~/ 2 + ring * 3) % 7 < 5) {
          canvas.set(x, y, '─', _Tone.orange);
        }
      }
      canvas.set(left, y, '╲', _Tone.violet);
      canvas.set(right, y, '╱', _Tone.violet);
    }
  }

  _Point _drawCoreDistrict() {
    final centerX = width ~/ 2;
    final baseY = height - 2;
    final districtWidth =
        math.max(20, math.min(48, width ~/ 3)).toInt();
    final left = centerX - districtWidth ~/ 2;
    final right = centerX + districtWidth ~/ 2;
    final roofY = math.max(12, (height * 0.64).round()).toInt();
    final shoulderY = math.min(baseY - 6, roofY + 5).toInt();

    canvas.set(left, shoulderY, '╭', _Tone.violet);
    canvas.hLine(left + 1, right - 1, shoulderY, '─', _Tone.violet);
    canvas.set(right, shoulderY, '╮', _Tone.violet);
    canvas.vLine(left, shoulderY + 1, baseY - 1, '│', _Tone.violet);
    canvas.vLine(right, shoulderY + 1, baseY - 1, '│', _Tone.violet);
    canvas.set(left, baseY, '╰', _Tone.violet);
    canvas.hLine(left + 1, right - 1, baseY, '─', _Tone.violet);
    canvas.set(right, baseY, '╯', _Tone.violet);

    final roofLeft = left - math.min(8, width ~/ 18).toInt();
    final roofRight = right + math.min(8, width ~/ 18).toInt();
    _stroke(
      _polyline(<_Point>[
        _Point(roofLeft, shoulderY),
        _Point(left + 4, roofY),
        _Point(right - 4, roofY),
        _Point(roofRight, shoulderY),
      ]),
      _Tone.violet,
    );

    final innerLeft = centerX - math.max(6, districtWidth ~/ 5).toInt();
    final innerRight = centerX + math.max(6, districtWidth ~/ 5).toInt();
    final socketY = math.max(7, roofY - 2).toInt();

    for (var y = shoulderY + 2; y < baseY; y += 2) {
      for (var x = left + 3; x < right - 2; x += 4) {
        final hash = _noise(x, y, 73 + tick ~/ 8);
        canvas.set(
          x,
          y,
          hash.isEven ? '·' : ':',
          hash % 3 == 0 ? _Tone.orange : _Tone.violet,
        );
      }
    }

    canvas.set(innerLeft, roofY, '╭', _Tone.violet);
    canvas.hLine(innerLeft + 1, innerRight - 1, roofY, '─', _Tone.violet);
    canvas.set(innerRight, roofY, '╮', _Tone.violet);
    canvas.vLine(innerLeft, socketY + 1, roofY - 1, '│', _Tone.violet);
    canvas.vLine(innerRight, socketY + 1, roofY - 1, '│', _Tone.violet);

    canvas.set(centerX - 2, socketY, '╲', _Tone.glow);
    canvas.set(centerX, socketY, '*', _Tone.white);
    canvas.set(centerX + 2, socketY, '╱', _Tone.glow);
    canvas.write(centerX - 3, roofY + 2, 'CINDER', _Tone.orange);

    final platformY = math.min(baseY - 3, shoulderY + 3).toInt();
    final platformLeft = math.max(1, roofLeft - 8).toInt();
    final platformRight = math.min(width - 2, roofRight + 8).toInt();
    canvas.hLine(
      platformLeft,
      platformRight,
      platformY,
      '═',
      _Tone.violetDim,
    );
    for (var x = platformLeft; x <= platformRight; x++) {
      if ((x + tick) % 9 == 0) {
        canvas.set(x, platformY, '◆', _Tone.orange);
      }
    }

    return _Point(centerX, socketY);
  }

  void _drawCableNetwork(_Point socket) {
    if (_towerTips.isEmpty) return;

    final selectedTips = <_Point>[];
    final divisor = math.max(4, width ~/ 28).toInt();
    final stride =
        math.max(1, _towerTips.length ~/ divisor).toInt();
    for (var i = 0; i < _towerTips.length; i += stride) {
      selectedTips.add(_towerTips[i]);
    }

    for (var i = 0; i < selectedTips.length; i++) {
      final tip = selectedTips[i];
      final side = tip.x < socket.x ? -1 : 1;
      final bendY = math.max(
        tip.y + 2,
        socket.y - 8 - (i % 4) * 2,
      ).toInt();
      final bendX = socket.x + side * (8 + (i % 3) * 5);
      final path = _polyline(<_Point>[
        tip,
        _Point(tip.x, math.min(height - 2, tip.y + 3 + i % 3).toInt()),
        _Point(bendX, bendY),
        _Point(socket.x + side * 3, socket.y - 2),
        socket,
      ]);
      if (path.length < 2) continue;
      _cables.add(path);
      _stroke(path, _Tone.violet, sparse: true, phase: i);
      _animateCable(path, i);
    }

    for (var i = 1; i < selectedTips.length; i++) {
      final left = selectedTips[i - 1];
      final right = selectedTips[i];
      if ((right.x - left.x).abs() > width ~/ 3) continue;
      final y = math.max(left.y, right.y).toInt() + 2 + i % 3;
      final path = _polyline(<_Point>[
        left,
        _Point(left.x, y),
        _Point(right.x, y),
        right,
      ]);
      _stroke(path, _Tone.violetDim, sparse: true, phase: i + 4);
      if ((tick + i * 7) % 19 < 10 || surging) {
        _drawMovingPulse(
          path,
          _positiveMod(tick * 3 + i * 13, math.max(1, path.length).toInt()),
          radius: surging ? 4 : 2,
          hot: i.isEven,
        );
      }
    }
  }

  void _animateCable(List<_Point> path, int seed) {
    final speed = surging ? 5 : 2 + (energy * 1.4).round();
    final offset = _positiveMod(tick * speed + seed * 19, path.length);
    _drawMovingPulse(
      path,
      offset,
      radius: surging ? 5 : 3,
      hot: seed.isEven,
    );

    if (surging || hovered) {
      final second = _positiveMod(offset + path.length ~/ 3, path.length);
      _drawMovingPulse(path, second, radius: 2, hot: !seed.isEven);
    }
  }

  void _drawElectricityBetweenCables() {
    if (_cables.length < 2) return;
    final arcCount = surging
        ? math.min(9, _cables.length - 1).toInt()
        : math.min(4, _cables.length - 1).toInt();

    for (var i = 0; i < arcCount; i++) {
      final first = _cables[i];
      final second = _cables[i + 1];
      if (first.length < 4 || second.length < 4) continue;
      final phase = _positiveMod(tick * 2 + i * 11, 100) / 100;
      final firstIndex = (phase * (first.length - 1)).round();
      final secondIndex = ((1 - phase * 0.65) * (second.length - 1)).round();
      final start = first[firstIndex.clamp(0, first.length - 1).toInt()];
      final end = second[secondIndex.clamp(0, second.length - 1).toInt()];
      if ((start.x - end.x).abs() > math.max(22, width ~/ 4).toInt()) {
        continue;
      }
      if ((start.y - end.y).abs() > math.max(12, height ~/ 3).toInt()) {
        continue;
      }
      if (!surging && (tick + i * 5) % 17 > 6) continue;
      _drawJaggedArc(start, end, seed: i * 97 + tick ~/ 2);
    }
  }

  void _drawJaggedArc(_Point start, _Point end, {required int seed}) {
    final segments = math.max(
      3,
      math.min(10, (start.x - end.x).abs() ~/ 4 + 3),
    ).toInt();
    final controls = <_Point>[start];
    for (var i = 1; i < segments; i++) {
      final progress = i / segments;
      final x = (start.x + (end.x - start.x) * progress).round();
      final y = (start.y + (end.y - start.y) * progress).round();
      final jitter = (_noise(x, y, seed + i) % 5) - 2;
      controls.add(_Point(x, y + jitter));
    }
    controls.add(end);

    final path = _polyline(controls);
    for (var i = 0; i < path.length; i++) {
      final point = path[i];
      if (i % 3 == 0) {
        canvas.set(point.x, point.y, i.isEven ? '*' : '+', _Tone.white);
      } else {
        canvas.set(point.x, point.y, i.isEven ? '╱' : '╲', _Tone.glow);
      }
      if (surging && i % 4 == 0) {
        canvas.set(point.x - 1, point.y, '·', _Tone.pink);
        canvas.set(point.x + 1, point.y, '·', _Tone.pink);
      }
    }
  }

  void _drawPlasmaColumn(_Point socket) {
    final top = math.max(1, height ~/ 18).toInt();
    final bottom = math.max(top + 2, socket.y - 1).toInt();
    final centerX = socket.x;
    final amplitude = surging ? 1.6 : hovered ? 1.25 : 1;

    for (var y = bottom; y >= top; y--) {
      final progress = (bottom - y) / math.max(1, bottom - top);
      final plume = math.sin((y * 0.72) + tick * 0.28) * 2.2;
      final turbulence = (_noise(centerX, y, tick ~/ 2) % 7) - 3;
      final drift = ((plume + turbulence * 0.45) * amplitude).round();
      final baseRadius = math.max(
        2,
        ((1 - progress) * math.max(2, width ~/ 36)).round(),
      ).toInt();
      final breathe = ((_noise(y, tick, 83) % 3) - 1) + (surging ? 2 : 0);
      final radius = math.max(1, baseRadius + breathe).toInt();
      final rowCenter = centerX + drift;

      for (var x = rowCenter - radius - 2; x <= rowCenter + radius + 2; x++) {
        final distance = (x - rowCenter).abs();
        final heat = _noise(x, y, tick + y * 3);
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

      if ((y + tick) % 5 == 0) {
        canvas.set(rowCenter - radius - 3, y, '·', _Tone.pink);
        canvas.set(rowCenter + radius + 3, y, '·', _Tone.pink);
      }
    }

    final crownY = math.max(1, top - 1).toInt();
    canvas.set(centerX - 2, crownY + 1, '╲', _Tone.pink);
    canvas.set(centerX, crownY, '*', _Tone.white);
    canvas.set(centerX + 2, crownY + 1, '╱', _Tone.pink);
  }

  void _drawEnergyHalo(_Point socket) {
    final maximumRadius = math.min(width ~/ 5, height ~/ 3).toInt();
    if (maximumRadius < 4) return;
    final rings = surging ? 4 : 2;

    for (var ring = 0; ring < rings; ring++) {
      final radius = 4 + _positiveMod(tick + ring * 7, maximumRadius);
      for (var dx = -radius; dx <= radius; dx++) {
        final dy = (radius - dx.abs()) ~/ 2;
        if ((_noise(dx, dy, tick + ring) % 4) != 0) continue;
        final tone = ring.isEven ? _Tone.pink : _Tone.orange;
        canvas.set(socket.x + dx, socket.y + dy, '·', tone);
        canvas.set(socket.x + dx, socket.y - dy, '·', tone);
      }
    }
  }

  void _drawTraffic() {
    for (var roadIndex = 0; roadIndex < _roads.length; roadIndex++) {
      final path = _roads[roadIndex];
      if (path.isEmpty) continue;
      final vehicleCount = math.max(2, width ~/ 48).toInt();
      for (var vehicle = 0; vehicle < vehicleCount; vehicle++) {
        final offset = _positiveMod(
          tick * (2 + roadIndex % 3) +
              vehicle * math.max(7, path.length ~/ vehicleCount).toInt(),
          path.length,
        );
        final point = path[offset];
        canvas.set(
          point.x,
          point.y,
          roadIndex.isEven ? '>' : '<',
          _Tone.white,
        );
        final tail = path[_positiveMod(offset - 1 - roadIndex % 2, path.length)];
        canvas.set(tail.x, tail.y, '─', _Tone.orange);
      }
    }
  }

  void _drawAmbientSparks() {
    final count = math.max(12, width * height ~/ 330).toInt();
    for (var i = 0; i < count; i++) {
      final seed = _noise(i, tick ~/ 2, 101);
      final x = _positiveMod(seed * 17 + tick * (i.isEven ? 1 : -1), width);
      final y = _positiveMod(seed * 7 - tick + i * 11, height);
      final phase = _positiveMod(tick + i * 3, 9);
      if (phase < 2) {
        canvas.set(x, y, phase == 0 ? '*' : '+', _Tone.white);
      } else if (phase < 5) {
        canvas.set(x, y, '·', _Tone.pink);
      } else {
        canvas.set(x, y, '.', _Tone.orange);
      }
    }
  }

  void _drawDrone() {
    if (width < 70 || height < 24) return;
    final span = math.max(12, width - 32).toInt();
    final travel = _positiveMod(tick, span * 2);
    final x = travel < span ? 16 + travel : 16 + (span * 2 - travel);
    final y = math.max(
      5,
      height ~/ 3 + (math.sin(tick * 0.13) * 3).round(),
    ).toInt();
    final facingRight = travel < span;
    canvas.write(x - 2, y, facingRight ? '─[>]' : '[<]─', _Tone.white);
    canvas.set(facingRight ? x - 3 : x + 3, y, '·', _Tone.orange);
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
        canvas.set(point.x, point.y, '*', _Tone.white);
      } else if (distance <= 1) {
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
      if (sparse && (i + phase + tick ~/ 4) % 6 == 0) continue;
      final previous = i > 0 ? path[i - 1] : path[i];
      final next = i < path.length - 1 ? path[i + 1] : path[i];
      canvas.set(path[i].x, path[i].y, _pathGlyph(previous, next), tone);
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
    final current = _rows[y][x];
    if (tone < current.tone) return;
    _rows[y][x] = _WorldCell(glyph, tone);
  }

  void write(int x, int y, String text, int tone) {
    for (var index = 0; index < text.length; index++) {
      set(x + index, y, text[index], tone);
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
}

abstract class _Tone {
  static const int empty = 0;
  static const int star = 1;
  static const int depth = 2;
  static const int violetDim = 3;
  static const int violet = 4;
  static const int orange = 5;
  static const int pink = 6;
  static const int glow = 7;
  static const int white = 8;
}

abstract class _Palette {
  static const Color voidBlack = Color.fromRGB(2, 3, 8);
  static const Color star = Color.fromRGB(75, 42, 96);
  static const Color depth = Color.fromRGB(50, 34, 73);
  static const Color violetDim = Color.fromRGB(91, 48, 132);
  static const Color violet = Color.fromRGB(190, 84, 246);
  static const Color pink = Color.fromRGB(255, 62, 184);
  static const Color orange = Color.fromRGB(232, 105, 27);
  static const Color glow = Color.fromRGB(255, 174, 56);
  static const Color white = Color.fromRGB(255, 241, 224);

  static TextStyle? styleFor(int tone) {
    return switch (tone) {
      _Tone.star => const TextStyle(color: star, fontWeight: FontWeight.dim),
      _Tone.depth => const TextStyle(color: depth, fontWeight: FontWeight.dim),
      _Tone.violetDim =>
        const TextStyle(color: violetDim, fontWeight: FontWeight.dim),
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
