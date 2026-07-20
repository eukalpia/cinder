import 'dart:async';
import 'dart:math' as math;

import 'package:cinder/cinder.dart';

/// Interactive cyber-city used as the live Cinder Web hero.
///
/// Everything visible here is rendered by Cinder into terminal cells. The
/// browser only hosts the isolated runtime through xterm.js.
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
  DateTime _lastTick = DateTime.now();
  int _frame = 0;
  double _frameMs = 16.7;
  final List<double> _frameHistory = <double>[
    16.7,
    17.2,
    15.9,
    16.4,
    18.1,
    16.0,
    16.8,
    17.5,
    16.2,
    15.8,
    16.6,
    17.1,
  ];

  bool _paused = false;
  bool _showDiff = true;
  bool _eventsExpanded = false;
  bool _coreBurst = false;
  int _selectedTower = 4;
  int? _hoveredTower;
  bool _coreHovered = false;
  double _droneX = 0;
  double _droneY = -1;

  final Set<int> _activeTowers = <int>{1, 4, 6, 9};
  final List<String> _events = <String>[
    'BOOT  WEB BACKEND READY',
    'SYNC  CELL BUFFER STABLE',
    'LINK  POINTER ROUTER ACTIVE',
    'CORE  CINDER ONLINE',
  ];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || _paused) return;
      final now = DateTime.now();
      final elapsed = now.difference(_lastTick).inMicroseconds / 1000;
      _lastTick = now;
      setState(() {
        _frame++;
        _frameMs = elapsed.clamp(0.1, 999.0).toDouble();
        if (_frame % 3 == 0) {
          _frameHistory
            ..add(_frameMs)
            ..removeAt(0);
        }
        if (_coreBurst && _frame % 34 == 0) {
          _coreBurst = false;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _safeExtent(constraints.maxWidth, fallback: 128);
          final height = _safeExtent(constraints.maxHeight, fallback: 42);

          if (width < 78 || height < 27) {
            return _buildCompact(width, height);
          }

          return Container(
            color: _Palette.voidBlack,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Text(
                    _buildStarfield(width, height),
                    softWrap: false,
                    style: const TextStyle(
                      color: _Palette.star,
                      fontWeight: FontWeight.dim,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Text(
                    _buildGrid(width, height),
                    softWrap: false,
                    style: const TextStyle(
                      color: _Palette.grid,
                      fontWeight: FontWeight.dim,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Text(
                    _buildRoads(width, height),
                    softWrap: false,
                    style: const TextStyle(color: _Palette.orangeDim),
                  ),
                ),
                ..._buildTowers(width, height),
                ..._buildCore(width, height),
                ..._buildDrone(width, height),
                if (_showDiff) ..._buildDamageRegions(width, height),
                _positionTopLeft(_buildStatePanel()),
                _positionTopRight(width, _buildDiffPanel()),
                _positionBottomLeft(height, _buildEventsPanel()),
                _positionBottomRight(width, height, _buildFramePanel()),
                Positioned(
                  left: math.max(0.0, width / 2 - 24).toDouble(),
                  top: 1,
                  width: 48,
                  height: 3,
                  child: Center(
                    child: Text(
                      _paused
                          ? 'CINDER CITY // PAUSED'
                          : 'CINDER CITY // LIVE CELL NETWORK',
                      style: TextStyle(
                        color:
                            _paused ? _Palette.orange : _Palette.violetBright,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: math.max(1.0, width / 2 - 39).toDouble(),
                  bottom: 0,
                  width: math.min(78, width - 2).toDouble(),
                  height: 2,
                  child: Center(
                    child: Text(
                      'ARROWS move drone  TAB select  ENTER toggle  D diff  E events  SPACE pause  R reset',
                      softWrap: false,
                      style: const TextStyle(
                        color: _Palette.label,
                        fontWeight: FontWeight.dim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompact(int width, int height) {
    final graph = _graph(_frameHistory, width: math.max(12, width - 22));
    return Container(
      color: _Palette.voidBlack,
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width.toDouble(),
            decoration: BoxDecoration(
              border: BoxBorder.all(
                color: _Palette.violet,
                style: BoxBorderStyle.dashed,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CINDER CITY',
                  style: TextStyle(
                    color: _Palette.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _paused ? 'PAUSED' : 'LIVE',
                  style: TextStyle(
                    color: _paused ? _Palette.orange : _Palette.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _pulseCore,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _coreHovered = true),
                  onExit: (_) => setState(() => _coreHovered = false),
                  child: Text(
                    _compactCore(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _coreBurst || _coreHovered
                          ? _Palette.orangeBright
                          : _Palette.violetBright,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            'FRAME ${_frameMs.toStringAsFixed(1)}ms  $graph',
            softWrap: false,
            style: const TextStyle(color: _Palette.violetBright),
          ),
          const Text(
            'TAB / ENTER nodes   D diff   SPACE pause   R reset',
            softWrap: false,
            style: TextStyle(color: _Palette.label),
          ),
        ],
      ),
    );
  }

  bool _handleKey(dynamic event) {
    final key = event.logicalKey;

    if (key == LogicalKey.arrowLeft) {
      _moveDrone(-2, 0);
    } else if (key == LogicalKey.arrowRight) {
      _moveDrone(2, 0);
    } else if (key == LogicalKey.arrowUp) {
      _moveDrone(0, -1);
    } else if (key == LogicalKey.arrowDown) {
      _moveDrone(0, 1);
    } else if (key == LogicalKey.tab) {
      setState(() {
        _selectedTower = (_selectedTower + 1) % _towers.length;
        _addEvent('SELECT  NODE ${_nodeId(_selectedTower)}');
      });
    } else if (key == LogicalKey.enter) {
      _toggleTower(_selectedTower);
    } else if (key == LogicalKey.keyD) {
      setState(() {
        _showDiff = !_showDiff;
        _addEvent('DIFF  ${_showDiff ? 'TRACE ENABLED' : 'TRACE HIDDEN'}');
      });
    } else if (key == LogicalKey.keyE) {
      setState(() {
        _eventsExpanded = !_eventsExpanded;
        _addEvent('EVENTS  ${_eventsExpanded ? 'EXPANDED' : 'COMPACT'}');
      });
    } else if (key == LogicalKey.space || key == LogicalKey.keyP) {
      setState(() {
        _paused = !_paused;
        _lastTick = DateTime.now();
        _addEvent(_paused ? 'CLOCK  PAUSED' : 'CLOCK  RESUMED');
      });
    } else if (key == LogicalKey.keyR) {
      _reset();
    } else {
      return false;
    }
    return true;
  }

  List<Widget> _buildTowers(int width, int height) {
    final widgets = <Widget>[];
    for (var i = 0; i < _towers.length; i++) {
      final spec = _towers[i];
      final art = _towerArt(spec.variant, i);
      final lines = art.split('\n');
      final artWidth = lines.fold<int>(
        0,
        (current, line) => math.max(current, line.length),
      );
      final artHeight = lines.length;
      final left = (spec.x * (width - artWidth - 4)).round().clamp(
            0,
            math.max(0, width - artWidth - 2),
          );
      final top = (spec.y * (height - artHeight - 4)).round().clamp(
            3,
            math.max(3, height - artHeight - 3),
          );
      final selected = i == _selectedTower;
      final hovered = i == _hoveredTower;
      final active = _activeTowers.contains(i);

      final color = hovered
          ? _Palette.orangeBright
          : selected
              ? _Palette.white
              : active
                  ? _Palette.violetBright
                  : _Palette.violetDim;

      widgets.add(
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: (artWidth + 2).toDouble(),
          height: (artHeight + 2).toDouble(),
          child: MouseRegion(
            onEnter: (_) {
              setState(() {
                _hoveredTower = i;
                _addEvent('HOVER  NODE ${_nodeId(i)}');
              });
            },
            onExit: (_) {
              if (_hoveredTower == i) {
                setState(() => _hoveredTower = null);
              }
            },
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedTower = i);
                _toggleTower(i);
              },
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: selected ? _Palette.selectionSurface : null,
                  border: selected || hovered
                      ? BoxBorder.all(
                          color: hovered ? _Palette.orange : _Palette.violet,
                          style: hovered
                              ? BoxBorderStyle.dotted
                              : BoxBorderStyle.dashed,
                        )
                      : null,
                ),
                child: Text(
                  art,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontWeight:
                        active || selected ? FontWeight.bold : FontWeight.dim,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildCore(int width, int height) {
    final core = _coreArt();
    final lines = core.split('\n');
    final coreWidth = lines.fold<int>(
      0,
      (current, line) => math.max(current, line.length),
    );
    final coreHeight = lines.length;
    final left = width / 2 - coreWidth / 2;
    final top = height / 2 - coreHeight / 2 + 1;
    final pulse = (_frame ~/ 3) % 4;
    final coreColor = _coreBurst || _coreHovered
        ? _Palette.orangeBright
        : pulse == 0
            ? _Palette.pink
            : _Palette.orange;

    return [
      Positioned(
        left: math.max(0.0, left - 5).toDouble(),
        top: math.max(2.0, top - 2).toDouble(),
        width: (coreWidth + 10).toDouble(),
        height: (coreHeight + 4).toDouble(),
        child: Text(
          _coreHalo(coreWidth + 10, coreHeight + 4),
          softWrap: false,
          style: TextStyle(
            color: _coreBurst ? _Palette.orange : _Palette.violetDim,
            fontWeight: FontWeight.dim,
          ),
        ),
      ),
      Positioned(
        left: math.max(0.0, left).toDouble(),
        top: math.max(3.0, top).toDouble(),
        width: coreWidth.toDouble(),
        height: coreHeight.toDouble(),
        child: MouseRegion(
          onEnter: (_) {
            setState(() {
              _coreHovered = true;
              _addEvent('HOVER  CINDER CORE');
            });
          },
          onExit: (_) => setState(() => _coreHovered = false),
          child: GestureDetector(
            onTap: _pulseCore,
            child: Text(
              core,
              softWrap: false,
              style: TextStyle(color: coreColor, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      Positioned(
        left: math.max(0.0, width / 2 - 6).toDouble(),
        top: math.max(3.0, height / 2 + 4).toDouble(),
        width: 12,
        height: 2,
        child: const Center(
          child: Text(
            '>_  CINDER',
            softWrap: false,
            style: TextStyle(
              color: _Palette.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDrone(int width, int height) {
    final left = (width / 2 + _droneX).clamp(24, width - 25).toDouble();
    final top = (height / 2 + _droneY).clamp(7, height - 8).toDouble();
    final glyph = (_frame ~/ 5).isEven ? '╼[▸]' : '─[▸]';
    return [
      Positioned(
        left: left,
        top: top,
        width: 6,
        height: 1,
        child: Text(
          glyph,
          softWrap: false,
          style: const TextStyle(
            color: _Palette.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDamageRegions(int width, int height) {
    final phase = (_frame ~/ 8) % 3;
    final regions = <_Region>[
      _Region(width * .29, height * .23, 18, 7),
      _Region(width * .63, height * .18, 20, 8),
      _Region(width * .47, height * .52, 16, 8),
    ];

    return [
      for (var i = 0; i < regions.length; i++)
        if (i != phase)
          Positioned(
            left: regions[i].left.clamp(0, width - regions[i].width).toDouble(),
            top: regions[i]
                .top
                .clamp(3, height - regions[i].height - 2)
                .toDouble(),
            width: regions[i].width.toDouble(),
            height: regions[i].height.toDouble(),
            child: Container(
              decoration: BoxDecoration(
                border: BoxBorder.all(
                  color: i.isEven ? _Palette.pinkDim : _Palette.orangeDim,
                  style: BoxBorderStyle.dotted,
                ),
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  ' Δ${12 + ((_frame + i * 17) % 88)} ',
                  style: TextStyle(
                    color: i.isEven ? _Palette.pink : _Palette.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Widget _buildStatePanel() {
    final active = _activeTowers.length;
    return _panel(
      width: 23,
      height: 9,
      title: 'STATE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _counterBox(active.toString().padLeft(2, '0'), 'SYS'),
              const SizedBox(width: 1),
              _counterBox(
                (_events.length % 100).toString().padLeft(2, '0'),
                'NET',
              ),
            ],
          ),
          const Spacer(),
          Text(
            _paused ? '◌ CLOCK HOLD' : '● CORE STABLE',
            style: TextStyle(
              color: _paused ? _Palette.orange : _Palette.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffPanel() {
    final low = (_frame * 7 + _activeTowers.length * 3) % 100;
    final high = (_frame * 11 + _selectedTower * 9) % 100;
    return _panel(
      width: 23,
      height: 9,
      title: 'DIFF',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _counterBox(low.toString().padLeft(2, '0'), 'LOW'),
              const SizedBox(width: 1),
              _counterBox(high.toString().padLeft(2, '0'), 'HIGH'),
            ],
          ),
          const Spacer(),
          Text(
            _showDiff ? 'TRACE  ${_miniBar(13)}' : 'TRACE  HIDDEN',
            softWrap: false,
            style: TextStyle(
              color: _showDiff ? _Palette.orange : _Palette.label,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsPanel() {
    final width = _eventsExpanded ? 34.0 : 27.0;
    final height = _eventsExpanded ? 14.0 : 10.0;
    final visible = _eventsExpanded ? 8 : 4;
    final rows = _events.reversed.take(visible).toList();

    return _panel(
      width: width,
      height: height,
      title: 'EVENTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in rows)
            Text(
              '> $event',
              softWrap: false,
              style: TextStyle(
                color: event.startsWith('HOVER')
                    ? _Palette.violetBright
                    : event.startsWith('NODE') || event.startsWith('CORE')
                        ? _Palette.orange
                        : _Palette.labelBright,
              ),
            ),
          const Spacer(),
          Text(
            _eventsExpanded ? '[E] COLLAPSE' : '[E] EXPAND',
            style: const TextStyle(
              color: _Palette.violet,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramePanel() {
    final average = _frameHistory.reduce((left, right) => left + right) /
        _frameHistory.length;
    return _panel(
      width: 23,
      height: 10,
      title: 'FRAME',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_frameMs.toStringAsFixed(1)}ms',
            style: const TextStyle(
              color: _Palette.violetBright,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _graph(_frameHistory, width: 17),
            softWrap: false,
            style: const TextStyle(color: _Palette.orange),
          ),
          const Spacer(),
          Text(
            'AVG ${average.toStringAsFixed(1)}  #${_frame.toString().padLeft(5, '0')}',
            softWrap: false,
            style: const TextStyle(color: _Palette.label),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required double width,
    required double height,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: _Palette.panel,
        border: BoxBorder.all(
          color: _Palette.panelLine,
          style: BoxBorderStyle.dashed,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _Palette.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _counterBox(String value, String label) {
    return Container(
      width: 8,
      height: 4,
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: _Palette.violetDim,
          style: BoxBorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _Palette.violetBright,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _Palette.label,
              fontWeight: FontWeight.dim,
            ),
          ),
        ],
      ),
    );
  }

  Positioned _positionTopLeft(Widget child) {
    return Positioned(left: 1, top: 1, width: 23, height: 9, child: child);
  }

  Positioned _positionTopRight(int width, Widget child) {
    return Positioned(
      left: math.max(1, width - 24).toDouble(),
      top: 1,
      width: 23,
      height: 9,
      child: child,
    );
  }

  Positioned _positionBottomLeft(int height, Widget child) {
    final panelHeight = _eventsExpanded ? 14.0 : 10.0;
    final panelWidth = _eventsExpanded ? 34.0 : 27.0;
    return Positioned(
      left: 1,
      top: math.max(10.0, height - panelHeight - 1).toDouble(),
      width: panelWidth,
      height: panelHeight,
      child: child,
    );
  }

  Positioned _positionBottomRight(int width, int height, Widget child) {
    return Positioned(
      left: math.max(1, width - 24).toDouble(),
      top: math.max(10, height - 11).toDouble(),
      width: 23,
      height: 10,
      child: child,
    );
  }

  void _moveDrone(double dx, double dy) {
    setState(() {
      _droneX = (_droneX + dx).clamp(-33, 33).toDouble();
      _droneY = (_droneY + dy).clamp(-12, 12).toDouble();
      _addEvent(
        'DRONE  X${_droneX.toInt().toString().padLeft(3)} '
        'Y${_droneY.toInt().toString().padLeft(3)}',
      );
    });
  }

  void _toggleTower(int index) {
    setState(() {
      _selectedTower = index;
      if (_activeTowers.remove(index)) {
        _addEvent('NODE ${_nodeId(index)}  SLEEP');
      } else {
        _activeTowers.add(index);
        _addEvent('NODE ${_nodeId(index)}  ACTIVE');
      }
    });
  }

  void _pulseCore() {
    setState(() {
      _coreBurst = true;
      _addEvent('CORE  MANUAL PULSE');
    });
  }

  void _reset() {
    setState(() {
      _paused = false;
      _showDiff = true;
      _eventsExpanded = false;
      _coreBurst = true;
      _selectedTower = 4;
      _hoveredTower = null;
      _droneX = 0;
      _droneY = -1;
      _activeTowers
        ..clear()
        ..addAll(<int>{1, 4, 6, 9});
      _events
        ..clear()
        ..addAll(<String>[
          'RESET  CITY STATE RESTORED',
          'SYNC  CELL BUFFER STABLE',
          'CORE  CINDER ONLINE',
        ]);
      _lastTick = DateTime.now();
    });
  }

  void _addEvent(String event) {
    if (_events.isNotEmpty && _events.last == event) return;
    _events.add(event);
    if (_events.length > 24) _events.removeAt(0);
  }

  String _buildStarfield(int width, int height) {
    final grid = List.generate(
      height,
      (_) => List<String>.filled(width, ' ', growable: false),
      growable: false,
    );
    final phase = _frame ~/ 4;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hash = (x * 73 + y * 151 + phase * 17) % 211;
        if (hash == 0 || hash == 19) {
          grid[y][x] = (x + y + phase).isEven ? '·' : '∙';
        } else if (hash == 41) {
          grid[y][x] = phase.isEven ? '+' : '×';
        } else if (hash == 97 && y > 3) {
          grid[y][x] = '^';
        }
      }
    }
    return _gridToString(grid);
  }

  String _buildGrid(int width, int height) {
    final grid = List.generate(
      height,
      (_) => List<String>.filled(width, ' ', growable: false),
      growable: false,
    );
    for (var y = 4; y < height - 2; y += 4) {
      for (var x = 0; x < width; x += 4) {
        grid[y][x] = '·';
      }
    }
    return _gridToString(grid);
  }

  String _buildRoads(int width, int height) {
    final grid = List.generate(
      height,
      (_) => List<String>.filled(width, ' ', growable: false),
      growable: false,
    );
    final cx = width ~/ 2;
    final cy = height ~/ 2 + 2;

    void put(int x, int y, String value) {
      if (x >= 0 && x < width && y >= 0 && y < height) {
        grid[y][x] = value;
      }
    }

    for (var x = 18; x < width - 18; x++) {
      if ((x + _frame ~/ 3) % 7 < 5) put(x, cy, '═');
      if ((x + 2) % 11 == 0) put(x, cy - 1, '·');
      if ((x + 7) % 13 == 0) put(x, cy + 1, '·');
    }

    for (var offset = 0; offset < math.min(cx - 16, cy - 4); offset++) {
      final pulse = (offset + _frame ~/ 4) % 9;
      if (pulse < 7) {
        put(cx - offset, cy - offset ~/ 2, '╲');
        put(cx + offset, cy - offset ~/ 2, '╱');
        put(cx - offset, cy + offset ~/ 2, '╱');
        put(cx + offset, cy + offset ~/ 2, '╲');
      }
    }

    for (var y = 10; y < height - 7; y++) {
      if ((y + _frame ~/ 5) % 5 != 0) {
        put(cx - 27, y, '║');
        put(cx + 27, y, '║');
      }
    }

    for (var x = 24; x < width - 24; x++) {
      if ((x + _frame ~/ 5) % 6 != 0) {
        put(x, 12, '─');
        put(x, height - 10, '─');
      }
    }

    return _gridToString(grid);
  }

  String _towerArt(int variant, int index) {
    final tick = (_frame ~/ 5 + index) % 4;
    final a = tick.isEven ? '◆' : '◇';
    final b = tick == 1 || tick == 2 ? '▓' : '▒';
    final c = _activeTowers.contains(index) ? '◉' : '○';

    switch (variant % 6) {
      case 0:
        return '''
       $c
      ╱│╲
    ╱─┴─╲
   ╱ $a $a ╲
  ╱───────╲
  │ $b  $b  │
  │  $a $a  │
  └───┬───┘''';
      case 1:
        return '''
       ╷
      ╱╲
     ╱$a ╲
   ╭─┴──┴─╮
  ╱ $b $a $b ╲
 ╱─────────╲
 │ $a  $b  $a │
 │  $b  $a  │
 └────┬────┘''';
      case 2:
        return '''
      $c
      │
    ╭─┴─╮
   ╱ $a $a ╲
  ╱──────╲
  │$b $a $b │
  │ $a $b  │
  │$b   $a │
  └──┬───┘''';
      case 3:
        return '''
        ╷
       ╱╲
      ╱$a ╲
   ╭──┴───╮
  ╱ $b $a $b ╲
 ╱────────╲
 │ $a $b $a │
 └───┬────┘''';
      case 4:
        return '''
      ╷
   ╭──┴──╮
  ╱ $a $b $a╲
 ╱────────╲
 │$b $a $b $a│
 │ $a $b  │
 └──┬─────┘''';
      default:
        return '''
       $c
      ╱╲
    ╭─┴──╮
   ╱$a $b $a╲
  ╱───────╲
  │ $b $a $b │
  └───┬───┘''';
    }
  }

  String _coreArt() {
    final phase = (_frame ~/ 3) % 4;
    final crown = const <String>['  ·  ', '  ✦  ', '  +  ', '  *  '][phase];
    final fill = _coreBurst
        ? '█'
        : phase.isEven
            ? '▓'
            : '▒';
    return '''
            $crown
            ╱│╲
          ╱╱│││╲╲
        ╱╱ $fill$fill$fill$fill$fill ╲╲
      ╱╱ $fill$fill█████$fill$fill ╲╲
     ╱  $fill█████████$fill  ╲
     ╲  $fill█████████$fill  ╱
      ╲╲ $fill$fill█████$fill$fill ╱╱
        ╲╲ $fill$fill$fill$fill$fill ╱╱
          ╲╲│││╱╱
            ╲│╱
       ╭─────────────╮
       │             │
       ╰─────────────╯''';
  }

  String _coreHalo(int width, int height) {
    final grid = List.generate(
      height,
      (_) => List<String>.filled(width, ' ', growable: false),
      growable: false,
    );
    final cx = width ~/ 2;
    final cy = height ~/ 2;
    for (var radius = 3; radius < math.min(width ~/ 2, height); radius += 3) {
      final phase = (radius + _frame ~/ 3) % 4;
      if (phase == 0) continue;
      for (var x = -radius; x <= radius; x++) {
        final y = (radius - x.abs()) ~/ 2;
        final char = phase.isEven ? '·' : ':';
        final x1 = cx + x;
        final y1 = cy + y;
        final y2 = cy - y;
        if (x1 >= 0 && x1 < width && y1 >= 0 && y1 < height) {
          grid[y1][x1] = char;
        }
        if (x1 >= 0 && x1 < width && y2 >= 0 && y2 < height) {
          grid[y2][x1] = char;
        }
      }
    }
    return _gridToString(grid);
  }

  String _compactCore() {
    final fill = _coreBurst
        ? '█'
        : (_frame ~/ 4).isEven
            ? '▓'
            : '▒';
    return '''
          ✦
         ╱│╲
       ╱ $fill$fill$fill ╲
     ╱ $fill█████$fill ╲
       $fill█████$fill
        ╲│╱
     ╭─────────╮
     │ CINDER  │
     ╰─────────╯''';
  }

  String _miniBar(int width) {
    const chars = '▁▂▃▄▅▆▇█';
    return List.generate(width, (index) {
      final value =
          (index * 5 + _frame ~/ 2 + _activeTowers.length) % chars.length;
      return chars[value];
    }).join();
  }

  String _graph(List<double> values, {required int width}) {
    const chars = '▁▂▃▄▅▆▇█';
    final source =
        values.length > width ? values.sublist(values.length - width) : values;
    if (source.isEmpty) return '';
    final low = source.reduce((a, b) => math.min(a, b).toDouble());
    final high = source.reduce((a, b) => math.max(a, b).toDouble());
    final span = math.max(0.1, high - low);
    final result = source.map((value) {
      final index = (((value - low) / span) * (chars.length - 1))
          .round()
          .clamp(0, chars.length - 1)
          .toInt();
      return chars[index];
    }).join();
    return result.padLeft(width, '▁');
  }

  String _gridToString(List<List<String>> grid) {
    return grid
        .map((row) => row.join().replaceFirst(RegExp(r'\s+$'), ''))
        .join('\n');
  }

  int _safeExtent(double value, {required int fallback}) {
    if (!value.isFinite || value <= 0) return fallback;
    return value.floor().clamp(1, 500).toInt();
  }

  String _nodeId(int index) => (index + 1).toString().padLeft(2, '0');

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class _TowerSpec {
  const _TowerSpec(this.x, this.y, this.variant);

  final double x;
  final double y;
  final int variant;
}

class _Region {
  const _Region(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final int width;
  final int height;
}

const _towers = <_TowerSpec>[
  _TowerSpec(.03, .10, 2),
  _TowerSpec(.14, .03, 0),
  _TowerSpec(.25, .17, 4),
  _TowerSpec(.36, .04, 1),
  _TowerSpec(.47, .13, 3),
  _TowerSpec(.61, .05, 2),
  _TowerSpec(.73, .02, 1),
  _TowerSpec(.86, .13, 4),
  _TowerSpec(.03, .57, 5),
  _TowerSpec(.17, .68, 3),
  _TowerSpec(.31, .58, 0),
  _TowerSpec(.68, .61, 5),
  _TowerSpec(.80, .69, 0),
  _TowerSpec(.90, .55, 2),
];

abstract class _Palette {
  static const Color voidBlack = Color.fromRGB(3, 4, 9);
  static const Color panel = Color.fromRGB(6, 7, 14);
  static const Color selectionSurface = Color.fromRGB(18, 10, 25);

  static const Color white = Color.fromRGB(239, 235, 246);
  static const Color labelBright = Color.fromRGB(188, 181, 201);
  static const Color label = Color.fromRGB(112, 105, 127);
  static const Color panelLine = Color.fromRGB(104, 83, 123);

  static const Color violetBright = Color.fromRGB(203, 95, 255);
  static const Color violet = Color.fromRGB(160, 67, 226);
  static const Color violetDim = Color.fromRGB(91, 48, 132);
  static const Color grid = Color.fromRGB(39, 27, 54);
  static const Color star = Color.fromRGB(103, 59, 135);

  static const Color pink = Color.fromRGB(255, 65, 181);
  static const Color pinkDim = Color.fromRGB(133, 38, 99);
  static const Color orangeBright = Color.fromRGB(255, 188, 66);
  static const Color orange = Color.fromRGB(255, 132, 35);
  static const Color orangeDim = Color.fromRGB(151, 76, 28);
  static const Color green = Color.fromRGB(113, 222, 139);
}
