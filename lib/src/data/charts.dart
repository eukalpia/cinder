import 'dart:math' as math;

import '../components/basic.dart';
import '../components/rich_text.dart';
import '../framework/framework.dart';
import '../style.dart';

/// One numeric observation in a cartesian chart.
class ChartPoint {
  const ChartPoint(this.x, this.y, {this.label, this.payload});

  final double x;
  final double y;
  final String? label;
  final Object? payload;
}

/// A named cartesian data series.
class ChartSeries {
  ChartSeries({
    required this.name,
    required List<ChartPoint> points,
    this.color,
    this.connectPoints = true,
    this.showPoints = true,
  }) : points = List<ChartPoint>.unmodifiable(points);

  ChartSeries.values({
    required this.name,
    required List<num> values,
    this.color,
    this.connectPoints = true,
    this.showPoints = true,
  }) : points = List<ChartPoint>.unmodifiable(<ChartPoint>[
          for (var index = 0; index < values.length; index++)
            ChartPoint(index.toDouble(), values[index].toDouble()),
        ]);

  final String name;
  final List<ChartPoint> points;
  final Color? color;
  final bool connectPoints;
  final bool showPoints;
}

/// A labeled bar value.
class ChartBar {
  const ChartBar({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;
}

/// One node in a terminal network graph.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    this.color,
    this.payload,
  });

  final Object id;
  final String label;
  final Color? color;
  final Object? payload;
}

/// One connection in a terminal network graph.
class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    this.label,
    this.color,
    this.directed = false,
    this.weight = 1,
  });

  final Object from;
  final Object to;
  final String? label;
  final Color? color;
  final bool directed;
  final double weight;
}

enum GraphLayout { circular, grid }

/// Visual configuration shared by all terminal-native charts.
class ChartThemeData {
  const ChartThemeData({
    this.axisColor = Colors.grey,
    this.gridColor = Colors.brightBlack,
    this.labelColor = Colors.grey,
    this.valueColor = Colors.white,
    this.backgroundColor,
    this.palette = const <Color>[
      Colors.blue,
      Colors.green,
      Colors.magenta,
      Colors.yellow,
      Colors.cyan,
      Colors.red,
      Colors.brightBlue,
      Colors.brightGreen,
    ],
    this.emptyMessage = 'No data',
  });

  final Color axisColor;
  final Color gridColor;
  final Color labelColor;
  final Color valueColor;
  final Color? backgroundColor;
  final List<Color> palette;
  final String emptyMessage;

  Color seriesColor(int index) {
    if (palette.isEmpty) return valueColor;
    return palette[index % palette.length];
  }
}

/// Axis and grid configuration for cartesian charts.
class CartesianChartStyle {
  const CartesianChartStyle({
    this.showAxes = true,
    this.showGrid = true,
    this.showLegend = true,
    this.showRange = true,
    this.xLabel,
    this.yLabel,
  });

  final bool showAxes;
  final bool showGrid;
  final bool showLegend;
  final bool showRange;
  final String? xLabel;
  final String? yLabel;
}

/// One terminal cell in a rasterized chart.
class ChartCell {
  const ChartCell(this.character, {this.color, this.backgroundColor});

  final String character;
  final Color? color;
  final Color? backgroundColor;

  TextStyle get style =>
      TextStyle(color: color, backgroundColor: backgroundColor);
}

/// Immutable terminal chart output.
class ChartFrame {
  ChartFrame(List<List<ChartCell>> rows)
      : rows = List<List<ChartCell>>.unmodifiable(
          rows.map(List<ChartCell>.unmodifiable),
        );

  final List<List<ChartCell>> rows;

  int get height => rows.length;
  int get width =>
      rows.isEmpty ? 0 : rows.map((row) => row.length).reduce(math.max);

  String toPlainText() {
    return rows
        .map((row) => row.map((cell) => cell.character).join())
        .join('\n');
  }
}

/// Pure chart rasterization utilities. They can be used without mounting widgets.
abstract final class ChartRasterizer {
  static const List<String> _sparkBlocks = <String>[
    '▁',
    '▂',
    '▃',
    '▄',
    '▅',
    '▆',
    '▇',
    '█',
  ];
  static const List<String> _heatBlocks = <String>[' ', '░', '▒', '▓', '█'];

  static ChartFrame sparkline(
    List<num> values, {
    int width = 24,
    Color? color,
    Color? backgroundColor,
  }) {
    final safeWidth = math.max(1, width);
    if (values.isEmpty) {
      return ChartFrame(<List<ChartCell>>[
        List<ChartCell>.filled(safeWidth, const ChartCell(' ')),
      ]);
    }
    final sampled = _sampleNumbers(values, safeWidth);
    final minValue = sampled.reduce(math.min).toDouble();
    final maxValue = sampled.reduce(math.max).toDouble();
    final span = maxValue - minValue;
    return ChartFrame(<List<ChartCell>>[
      <ChartCell>[
        for (final value in sampled)
          ChartCell(
            _sparkBlocks[span == 0
                ? _sparkBlocks.length ~/ 2
                : (((value - minValue) / span) * (_sparkBlocks.length - 1))
                    .round()
                    .clamp(0, _sparkBlocks.length - 1)],
            color: color,
            backgroundColor: backgroundColor,
          ),
      ],
    ]);
  }

  static ChartFrame line(
    List<ChartSeries> series, {
    int width = 48,
    int height = 14,
    ChartThemeData theme = const ChartThemeData(),
    CartesianChartStyle style = const CartesianChartStyle(),
    double? minX,
    double? maxX,
    double? minY,
    double? maxY,
  }) {
    final safeWidth = math.max(style.showAxes ? 4 : 2, width);
    final safeHeight = math.max(style.showAxes ? 4 : 2, height);
    final nonEmpty = series.where((item) => item.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return _emptyFrame(safeWidth, safeHeight, theme);

    final bounds = _resolveBounds(
      nonEmpty,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
    final left = style.showAxes ? 1 : 0;
    final bottom = style.showAxes ? 1 : 0;
    final plotWidth = math.max(1, safeWidth - left);
    final plotHeight = math.max(1, safeHeight - bottom);
    final frame = _blank(safeWidth, safeHeight, theme.backgroundColor);

    if (style.showGrid) {
      _drawGrid(frame, left, 0, plotWidth, plotHeight, theme.gridColor);
    }
    if (style.showAxes) {
      _drawAxes(frame, left, plotHeight, plotWidth, theme.axisColor);
    }

    final canvas = _BrailleCanvas(plotWidth, plotHeight);
    for (var seriesIndex = 0; seriesIndex < nonEmpty.length; seriesIndex++) {
      final item = nonEmpty[seriesIndex];
      final color = item.color ?? theme.seriesColor(seriesIndex);
      final mapped = <_RasterPoint>[
        for (final point in item.points)
          _mapToBraille(point, bounds, plotWidth, plotHeight),
      ];
      if (item.connectPoints && mapped.length > 1) {
        for (var index = 1; index < mapped.length; index++) {
          canvas.drawLine(mapped[index - 1], mapped[index], color);
        }
      }
      if (item.showPoints) {
        for (final point in mapped) {
          canvas.set(point.x, point.y, color);
        }
      }
    }
    _compositeBraille(frame, canvas, left, 0);
    return ChartFrame(frame);
  }

  static ChartFrame scatter(
    List<ChartSeries> series, {
    int width = 48,
    int height = 14,
    ChartThemeData theme = const ChartThemeData(),
    CartesianChartStyle style = const CartesianChartStyle(),
    double? minX,
    double? maxX,
    double? minY,
    double? maxY,
  }) {
    final pointsOnly = <ChartSeries>[
      for (final item in series)
        ChartSeries(
          name: item.name,
          points: item.points,
          color: item.color,
          connectPoints: false,
          showPoints: true,
        ),
    ];
    return line(
      pointsOnly,
      width: width,
      height: height,
      theme: theme,
      style: style,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  static ChartFrame horizontalBars(
    List<ChartBar> bars, {
    int width = 48,
    int labelWidth = 12,
    ChartThemeData theme = const ChartThemeData(),
    bool showValues = true,
    String Function(double value)? valueFormatter,
  }) {
    final safeWidth = math.max(8, width);
    if (bars.isEmpty) return _emptyFrame(safeWidth, 1, theme);
    final formatter = valueFormatter ?? _defaultNumberFormat;
    final maxAbs = bars.map((bar) => bar.value.abs()).fold<double>(0, math.max);
    final valueTexts = <String>[for (final bar in bars) formatter(bar.value)];
    final valueWidth = showValues
        ? valueTexts.map((value) => value.length).fold<int>(0, math.max) + 1
        : 0;
    final effectiveLabelWidth = math.min(
      labelWidth,
      math.max(1, safeWidth ~/ 3),
    );
    final barWidth = math.max(
      1,
      safeWidth - effectiveLabelWidth - valueWidth - 1,
    );
    final rows = <List<ChartCell>>[];

    for (var index = 0; index < bars.length; index++) {
      final bar = bars[index];
      final color = bar.color ?? theme.seriesColor(index);
      final label = _fitLabel(bar.label, effectiveLabelWidth);
      final fraction = maxAbs == 0 ? 0.0 : bar.value.abs() / maxAbs;
      final filled = (fraction * barWidth).round().clamp(0, barWidth);
      final row = <ChartCell>[
        ...label
            .split('')
            .map((char) => ChartCell(char, color: theme.labelColor)),
        const ChartCell(' '),
        for (var cell = 0; cell < barWidth; cell++)
          ChartCell(cell < filled ? '█' : ' ', color: color),
      ];
      if (showValues) {
        final value = valueTexts[index].padLeft(valueWidth);
        row.addAll(
          value
              .split('')
              .map((char) => ChartCell(char, color: theme.valueColor)),
        );
      }
      rows.add(row);
    }
    return ChartFrame(rows);
  }

  static ChartFrame verticalBars(
    List<ChartBar> bars, {
    int width = 48,
    int height = 14,
    ChartThemeData theme = const ChartThemeData(),
    bool showAxis = true,
  }) {
    final safeWidth = math.max(4, width);
    final safeHeight = math.max(3, height);
    if (bars.isEmpty) return _emptyFrame(safeWidth, safeHeight, theme);
    final plotHeight = safeHeight - (showAxis ? 2 : 0);
    final gap = bars.length > 1 ? 1 : 0;
    final barWidth = math.max(
      1,
      (safeWidth - gap * (bars.length - 1)) ~/ bars.length,
    );
    final usedWidth = barWidth * bars.length + gap * (bars.length - 1);
    final startX = math.max(0, (safeWidth - usedWidth) ~/ 2);
    final minValue = math.min(
      0.0,
      bars.map((bar) => bar.value).reduce(math.min),
    );
    final maxValue = math.max(
      0.0,
      bars.map((bar) => bar.value).reduce(math.max),
    );
    final span = maxValue - minValue == 0 ? 1.0 : maxValue - minValue;
    final zeroY = ((maxValue / span) * (plotHeight - 1)).round();
    final frame = _blank(safeWidth, safeHeight, theme.backgroundColor);

    for (var index = 0; index < bars.length; index++) {
      final bar = bars[index];
      final color = bar.color ?? theme.seriesColor(index);
      final valueY = ((maxValue - bar.value) / span * (plotHeight - 1)).round();
      final top = math.min(zeroY, valueY);
      final bottom = math.max(zeroY, valueY);
      final xStart = startX + index * (barWidth + gap);
      for (var y = top; y <= bottom; y++) {
        for (var x = xStart; x < xStart + barWidth && x < safeWidth; x++) {
          frame[y][x] = ChartCell('█', color: color);
        }
      }
      if (showAxis && index * (barWidth + gap) + startX < safeWidth) {
        final label = _fitLabel(bar.label, barWidth);
        for (var offset = 0;
            offset < label.length && xStart + offset < safeWidth;
            offset++) {
          frame[safeHeight - 1][xStart + offset] = ChartCell(
            label[offset],
            color: theme.labelColor,
          );
        }
      }
    }
    if (showAxis) {
      final axisY = math.min(plotHeight, safeHeight - 2);
      for (var x = 0; x < safeWidth; x++) {
        frame[axisY][x] = ChartCell('─', color: theme.axisColor);
      }
    }
    return ChartFrame(frame);
  }

  static ChartFrame heatmap(
    List<List<num>> values, {
    ChartThemeData theme = const ChartThemeData(),
    Color cold = Colors.blue,
    Color hot = Colors.red,
    bool useColor = true,
  }) {
    if (values.isEmpty || values.every((row) => row.isEmpty)) {
      return _emptyFrame(8, 1, theme);
    }
    final width = values.map((row) => row.length).fold<int>(0, math.max);
    final flattened = <double>[
      for (final row in values)
        for (final value in row) value.toDouble(),
    ];
    final minValue = flattened.reduce(math.min);
    final maxValue = flattened.reduce(math.max);
    final span = maxValue - minValue;
    final rows = <List<ChartCell>>[];
    for (final row in values) {
      final cells = <ChartCell>[];
      for (var x = 0; x < width; x++) {
        if (x >= row.length) {
          cells.add(const ChartCell(' '));
          continue;
        }
        final normalized =
            span == 0 ? 0.5 : (row[x].toDouble() - minValue) / span;
        final level = (normalized * (_heatBlocks.length - 1)).round().clamp(
              0,
              _heatBlocks.length - 1,
            );
        cells.add(
          ChartCell(
            _heatBlocks[level],
            color:
                useColor ? Color.lerp(cold, hot, normalized) : theme.valueColor,
          ),
        );
      }
      rows.add(cells);
    }
    return ChartFrame(rows);
  }

  static ChartFrame donut(
    List<ChartBar> slices, {
    int width = 24,
    int height = 12,
    double innerRadius = 0.45,
    ChartThemeData theme = const ChartThemeData(),
  }) {
    final safeWidth = math.max(8, width);
    final safeHeight = math.max(5, height);
    final positive = slices.where((slice) => slice.value > 0).toList();
    final total = positive.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return _emptyFrame(safeWidth, safeHeight, theme);
    final frame = _blank(safeWidth, safeHeight, theme.backgroundColor);
    final centerX = (safeWidth - 1) / 2;
    final centerY = (safeHeight - 1) / 2;
    final radiusX = math.max(1.0, centerX);
    final radiusY = math.max(1.0, centerY);
    final cumulative = <double>[];
    var running = 0.0;
    for (final slice in positive) {
      running += slice.value / total;
      cumulative.add(running);
    }

    for (var y = 0; y < safeHeight; y++) {
      for (var x = 0; x < safeWidth; x++) {
        final dx = (x - centerX) / radiusX;
        final dy = (y - centerY) / radiusY;
        final radius = math.sqrt(dx * dx + dy * dy);
        if (radius > 1 || radius < innerRadius.clamp(0.0, 0.9)) continue;
        var angle = math.atan2(dy, dx) / (2 * math.pi);
        if (angle < 0) angle += 1;
        var segment = cumulative.indexWhere((end) => angle <= end);
        if (segment < 0) segment = cumulative.length - 1;
        frame[y][x] = ChartCell(
          radius > 0.88 || radius < innerRadius + 0.08 ? '▓' : '█',
          color: positive[segment].color ?? theme.seriesColor(segment),
        );
      }
    }
    return ChartFrame(frame);
  }

  static ChartFrame gauge(
    double value, {
    double min = 0,
    double max = 100,
    int width = 32,
    ChartThemeData theme = const ChartThemeData(),
    Color? color,
    String Function(double value)? valueFormatter,
  }) {
    final safeWidth = math.max(8, width);
    final span = max - min == 0 ? 1.0 : max - min;
    final normalized = ((value - min) / span).clamp(0.0, 1.0);
    final formatter = valueFormatter ?? _defaultNumberFormat;
    final label = formatter(value);
    final innerWidth = math.max(1, safeWidth - 2);
    final filled = (innerWidth * normalized).round().clamp(0, innerWidth);
    final effectiveColor = color ?? theme.seriesColor(0);
    final first = <ChartCell>[
      ChartCell('▕', color: theme.axisColor),
      for (var index = 0; index < innerWidth; index++)
        ChartCell(index < filled ? '█' : '░', color: effectiveColor),
      ChartCell('▏', color: theme.axisColor),
    ];
    final centeredLabel = label.length >= safeWidth
        ? label.substring(0, safeWidth)
        : '${' ' * ((safeWidth - label.length) ~/ 2)}$label';
    return ChartFrame(<List<ChartCell>>[
      first,
      <ChartCell>[
        ...centeredLabel
            .padRight(safeWidth)
            .split('')
            .map((char) => ChartCell(char, color: theme.valueColor)),
      ],
    ]);
  }

  /// Renders a network graph with deterministic circular or grid layout.
  static ChartFrame networkGraph(
    List<GraphNode> nodes,
    List<GraphEdge> edges, {
    int width = 56,
    int height = 18,
    GraphLayout layout = GraphLayout.circular,
    ChartThemeData theme = const ChartThemeData(),
    int maxLabelWidth = 12,
  }) {
    final safeWidth = math.max(12, width);
    final safeHeight = math.max(5, height);
    if (nodes.isEmpty) return _emptyFrame(safeWidth, safeHeight, theme);

    final frame = _blank(safeWidth, safeHeight, theme.backgroundColor);
    final positions = <Object, _GraphPosition>{};
    if (layout == GraphLayout.grid) {
      final columns = math.max(1, math.sqrt(nodes.length).ceil());
      final rows = (nodes.length / columns).ceil();
      for (var index = 0; index < nodes.length; index++) {
        final column = index % columns;
        final row = index ~/ columns;
        final x = ((column + 0.5) * safeWidth / columns)
            .round()
            .clamp(1, safeWidth - 2);
        final y =
            ((row + 0.5) * safeHeight / rows).round().clamp(1, safeHeight - 2);
        positions[nodes[index].id] = _GraphPosition(x, y);
      }
    } else {
      final centerX = (safeWidth - 1) / 2;
      final centerY = (safeHeight - 1) / 2;
      final radiusX = math.max(2.0, centerX - maxLabelWidth / 2 - 1);
      final radiusY = math.max(1.0, centerY - 1);
      for (var index = 0; index < nodes.length; index++) {
        final angle = -math.pi / 2 + (2 * math.pi * index / nodes.length);
        positions[nodes[index].id] = _GraphPosition(
          (centerX + math.cos(angle) * radiusX).round().clamp(1, safeWidth - 2),
          (centerY + math.sin(angle) * radiusY)
              .round()
              .clamp(1, safeHeight - 2),
        );
      }
    }

    for (final edge in edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null || from == to) continue;
      final color = edge.color ?? theme.gridColor;
      _drawGraphEdge(frame, from, to, color, directed: edge.directed);
      final label = edge.label;
      if (label != null && label.isNotEmpty) {
        final midX = ((from.x + to.x) / 2).round();
        final midY = ((from.y + to.y) / 2).round();
        _drawGraphText(frame, midX, midY, label, color, centered: true);
      }
    }

    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final position = positions[node.id]!;
      final color = node.color ?? theme.seriesColor(index);
      final label =
          _fitLabel(node.label, math.max(1, maxLabelWidth)).trimRight();
      _drawGraphText(
        frame,
        position.x,
        position.y,
        '[$label]',
        color,
        centered: true,
        bold: true,
      );
    }
    return ChartFrame(frame);
  }

  static void _drawGraphEdge(
    List<List<ChartCell>> frame,
    _GraphPosition from,
    _GraphPosition to,
    Color color, {
    required bool directed,
  }) {
    var x0 = from.x;
    var y0 = from.y;
    final x1 = to.x;
    final y1 = to.y;
    final dx = (x1 - x0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs();
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;
    while (true) {
      if (!(x0 == from.x && y0 == from.y) && !(x0 == x1 && y0 == y1)) {
        final char = dx > -dy * 2
            ? '─'
            : -dy > dx * 2
                ? '│'
                : sx == sy
                    ? '╲'
                    : '╱';
        if (y0 >= 0 && y0 < frame.length && x0 >= 0 && x0 < frame[y0].length) {
          frame[y0][x0] = ChartCell(char, color: color);
        }
      }
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
    if (directed) {
      final arrowX = (to.x - sx).clamp(0, frame.first.length - 1);
      final arrowY = (to.y - sy).clamp(0, frame.length - 1);
      final arrow = dx >= -dy ? (sx > 0 ? '›' : '‹') : (sy > 0 ? '▼' : '▲');
      frame[arrowY][arrowX] = ChartCell(arrow, color: color);
    }
  }

  static void _drawGraphText(
    List<List<ChartCell>> frame,
    int x,
    int y,
    String text,
    Color color, {
    bool centered = false,
    bool bold = false,
  }) {
    if (y < 0 || y >= frame.length) return;
    var start = centered ? x - text.length ~/ 2 : x;
    for (var index = 0; index < text.length; index++) {
      final target = start + index;
      if (target < 0 || target >= frame[y].length) continue;
      frame[y][target] = ChartCell(
        text[index],
        color: color,
        backgroundColor: bold ? color.withOpacity(0.12) : null,
      );
    }
  }

  static ChartFrame histogram(
    List<num> samples, {
    int bins = 10,
    int width = 48,
    int height = 12,
    ChartThemeData theme = const ChartThemeData(),
  }) {
    if (samples.isEmpty) return _emptyFrame(width, height, theme);
    final safeBins = bins.clamp(1, math.max(1, width ~/ 2)).toInt();
    final doubles = samples.map((value) => value.toDouble()).toList();
    final minValue = doubles.reduce(math.min);
    final maxValue = doubles.reduce(math.max);
    final span = maxValue - minValue;
    final counts = List<int>.filled(safeBins, 0);
    for (final sample in doubles) {
      final index = span == 0
          ? safeBins ~/ 2
          : (((sample - minValue) / span) * safeBins).floor().clamp(
                0,
                safeBins - 1,
              );
      counts[index]++;
    }
    return verticalBars(
      <ChartBar>[
        for (var index = 0; index < counts.length; index++)
          ChartBar(label: '${index + 1}', value: counts[index].toDouble()),
      ],
      width: width,
      height: height,
      theme: theme,
      showAxis: true,
    );
  }

  static List<List<ChartCell>> _blank(
    int width,
    int height,
    Color? backgroundColor,
  ) {
    return List<List<ChartCell>>.generate(
      height,
      (_) => List<ChartCell>.generate(
        width,
        (_) => ChartCell(' ', backgroundColor: backgroundColor),
      ),
    );
  }

  static ChartFrame _emptyFrame(int width, int height, ChartThemeData theme) {
    final safeWidth = math.max(1, width);
    final safeHeight = math.max(1, height);
    final frame = _blank(safeWidth, safeHeight, theme.backgroundColor);
    final message = _fitLabel(theme.emptyMessage, safeWidth);
    final y = safeHeight ~/ 2;
    final start = math.max(0, (safeWidth - message.length) ~/ 2);
    for (var index = 0; index < message.length; index++) {
      frame[y][start + index] = ChartCell(
        message[index],
        color: theme.labelColor,
      );
    }
    return ChartFrame(frame);
  }

  static _ChartBounds _resolveBounds(
    List<ChartSeries> series, {
    double? minX,
    double? maxX,
    double? minY,
    double? maxY,
  }) {
    final points = <ChartPoint>[for (final item in series) ...item.points];
    var resolvedMinX = minX ?? points.map((point) => point.x).reduce(math.min);
    var resolvedMaxX = maxX ?? points.map((point) => point.x).reduce(math.max);
    var resolvedMinY = minY ?? points.map((point) => point.y).reduce(math.min);
    var resolvedMaxY = maxY ?? points.map((point) => point.y).reduce(math.max);
    if (resolvedMinX == resolvedMaxX) {
      resolvedMinX -= 0.5;
      resolvedMaxX += 0.5;
    }
    if (resolvedMinY == resolvedMaxY) {
      resolvedMinY -= 0.5;
      resolvedMaxY += 0.5;
    }
    return _ChartBounds(resolvedMinX, resolvedMaxX, resolvedMinY, resolvedMaxY);
  }

  static _RasterPoint _mapToBraille(
    ChartPoint point,
    _ChartBounds bounds,
    int width,
    int height,
  ) {
    final normalizedX = (point.x - bounds.minX) / (bounds.maxX - bounds.minX);
    final normalizedY = (point.y - bounds.minY) / (bounds.maxY - bounds.minY);
    return _RasterPoint(
      (normalizedX * (width * 2 - 1)).round().clamp(0, width * 2 - 1),
      ((1 - normalizedY) * (height * 4 - 1)).round().clamp(0, height * 4 - 1),
    );
  }

  static void _drawGrid(
    List<List<ChartCell>> frame,
    int left,
    int top,
    int width,
    int height,
    Color color,
  ) {
    for (var division = 1; division < 4; division++) {
      final x = left + (width * division / 4).round();
      final y = top + (height * division / 4).round();
      if (x < frame.first.length) {
        for (var row = top; row < top + height && row < frame.length; row++) {
          frame[row][x] = ChartCell('┊', color: color);
        }
      }
      if (y < frame.length) {
        for (var column = left;
            column < left + width && column < frame[y].length;
            column++) {
          frame[y][column] = ChartCell('┄', color: color);
        }
      }
    }
  }

  static void _drawAxes(
    List<List<ChartCell>> frame,
    int left,
    int plotHeight,
    int plotWidth,
    Color color,
  ) {
    for (var y = 0; y < plotHeight; y++) {
      frame[y][0] = ChartCell('│', color: color);
    }
    final axisY = math.min(plotHeight, frame.length - 1);
    frame[axisY][0] = ChartCell('└', color: color);
    for (var x = left; x < left + plotWidth && x < frame[axisY].length; x++) {
      frame[axisY][x] = ChartCell('─', color: color);
    }
  }

  static void _compositeBraille(
    List<List<ChartCell>> frame,
    _BrailleCanvas canvas,
    int left,
    int top,
  ) {
    for (var y = 0; y < canvas.height; y++) {
      for (var x = 0; x < canvas.width; x++) {
        final cell = canvas.cellAt(x, y);
        if (cell == null || cell.mask == 0) continue;
        final targetY = top + y;
        final targetX = left + x;
        if (targetY >= frame.length || targetX >= frame[targetY].length) {
          continue;
        }
        frame[targetY][targetX] = ChartCell(
          String.fromCharCode(0x2800 + cell.mask),
          color: cell.color,
        );
      }
    }
  }

  static List<double> _sampleNumbers(List<num> values, int width) {
    if (values.length == width) {
      return values.map((value) => value.toDouble()).toList();
    }
    if (values.length < width) {
      return <double>[
        for (var index = 0; index < width; index++)
          values[(index * values.length / width).floor().clamp(
                    0,
                    values.length - 1,
                  )]
              .toDouble(),
      ];
    }
    return <double>[
      for (var index = 0; index < width; index++)
        _bucketAverage(
          values,
          index * values.length ~/ width,
          (index + 1) * values.length ~/ width,
        ),
    ];
  }

  static double _bucketAverage(List<num> values, int start, int end) {
    final safeEnd = math.max(start + 1, end).clamp(1, values.length);
    var sum = 0.0;
    for (var index = start; index < safeEnd; index++) {
      sum += values[index].toDouble();
    }
    return sum / (safeEnd - start);
  }
}

/// Compact one-row trend visualization.
class SparklineChart extends StatelessWidget {
  const SparklineChart({
    super.key,
    required this.values,
    this.width,
    this.color,
    this.theme = const ChartThemeData(),
  });

  final List<num> values;
  final int? width;
  final Color? color;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 24);
        return _ChartFrameWidget(
          frame: ChartRasterizer.sparkline(
            values,
            width: resolvedWidth,
            color: color ?? theme.seriesColor(0),
            backgroundColor: theme.backgroundColor,
          ),
        );
      },
    );
  }
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.width,
    this.height = 14,
    this.title,
    this.theme = const ChartThemeData(),
    this.style = const CartesianChartStyle(),
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
  });

  final List<ChartSeries> series;
  final int? width;
  final int height;
  final String? title;
  final ChartThemeData theme;
  final CartesianChartStyle style;
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 48);
        return _ChartPanel(
          title: title,
          legend: style.showLegend ? _legendEntries(series, theme) : const [],
          theme: theme,
          child: _ChartFrameWidget(
            frame: ChartRasterizer.line(
              series,
              width: resolvedWidth,
              height: height,
              theme: theme,
              style: style,
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
            ),
          ),
        );
      },
    );
  }
}

class ScatterChart extends StatelessWidget {
  const ScatterChart({
    super.key,
    required this.series,
    this.width,
    this.height = 14,
    this.title,
    this.theme = const ChartThemeData(),
    this.style = const CartesianChartStyle(),
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
  });

  final List<ChartSeries> series;
  final int? width;
  final int height;
  final String? title;
  final ChartThemeData theme;
  final CartesianChartStyle style;
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 48);
        return _ChartPanel(
          title: title,
          legend: style.showLegend ? _legendEntries(series, theme) : const [],
          theme: theme,
          child: _ChartFrameWidget(
            frame: ChartRasterizer.scatter(
              series,
              width: resolvedWidth,
              height: height,
              theme: theme,
              style: style,
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
            ),
          ),
        );
      },
    );
  }
}

class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.bars,
    this.width,
    this.height = 14,
    this.title,
    this.orientation = Axis.horizontal,
    this.labelWidth = 12,
    this.showValues = true,
    this.valueFormatter,
    this.theme = const ChartThemeData(),
  });

  final List<ChartBar> bars;
  final int? width;
  final int height;
  final String? title;
  final Axis orientation;
  final int labelWidth;
  final bool showValues;
  final String Function(double value)? valueFormatter;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 48);
        final frame = orientation == Axis.horizontal
            ? ChartRasterizer.horizontalBars(
                bars,
                width: resolvedWidth,
                labelWidth: labelWidth,
                theme: theme,
                showValues: showValues,
                valueFormatter: valueFormatter,
              )
            : ChartRasterizer.verticalBars(
                bars,
                width: resolvedWidth,
                height: height,
                theme: theme,
              );
        return _ChartPanel(
          title: title,
          theme: theme,
          child: _ChartFrameWidget(frame: frame),
        );
      },
    );
  }
}

class NetworkGraphChart extends StatelessWidget {
  const NetworkGraphChart({
    super.key,
    required this.nodes,
    required this.edges,
    this.width,
    this.height = 18,
    this.layout = GraphLayout.circular,
    this.title,
    this.maxLabelWidth = 12,
    this.theme = const ChartThemeData(),
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final int? width;
  final int height;
  final GraphLayout layout;
  final String? title;
  final int maxLabelWidth;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 56);
        return _ChartPanel(
          title: title,
          theme: theme,
          child: _ChartFrameWidget(
            frame: ChartRasterizer.networkGraph(
              nodes,
              edges,
              width: resolvedWidth,
              height: height,
              layout: layout,
              maxLabelWidth: maxLabelWidth,
              theme: theme,
            ),
          ),
        );
      },
    );
  }
}

class HistogramChart extends StatelessWidget {
  const HistogramChart({
    super.key,
    required this.samples,
    this.bins = 10,
    this.width,
    this.height = 12,
    this.title,
    this.theme = const ChartThemeData(),
  });

  final List<num> samples;
  final int bins;
  final int? width;
  final int height;
  final String? title;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 48);
        return _ChartPanel(
          title: title,
          theme: theme,
          child: _ChartFrameWidget(
            frame: ChartRasterizer.histogram(
              samples,
              bins: bins,
              width: resolvedWidth,
              height: height,
              theme: theme,
            ),
          ),
        );
      },
    );
  }
}

class HeatmapChart extends StatelessWidget {
  const HeatmapChart({
    super.key,
    required this.values,
    this.title,
    this.cold = Colors.blue,
    this.hot = Colors.red,
    this.useColor = true,
    this.theme = const ChartThemeData(),
  });

  final List<List<num>> values;
  final String? title;
  final Color cold;
  final Color hot;
  final bool useColor;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _ChartPanel(
      title: title,
      theme: theme,
      child: _ChartFrameWidget(
        frame: ChartRasterizer.heatmap(
          values,
          theme: theme,
          cold: cold,
          hot: hot,
          useColor: useColor,
        ),
      ),
    );
  }
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.width = 24,
    this.height = 12,
    this.innerRadius = 0.45,
    this.title,
    this.showLegend = true,
    this.theme = const ChartThemeData(),
  });

  final List<ChartBar> slices;
  final int width;
  final int height;
  final double innerRadius;
  final String? title;
  final bool showLegend;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _ChartPanel(
      title: title,
      theme: theme,
      legend: showLegend
          ? <_LegendEntry>[
              for (var index = 0; index < slices.length; index++)
                _LegendEntry(
                  slices[index].label,
                  slices[index].color ?? theme.seriesColor(index),
                ),
            ]
          : const [],
      child: _ChartFrameWidget(
        frame: ChartRasterizer.donut(
          slices,
          width: width,
          height: height,
          innerRadius: innerRadius,
          theme: theme,
        ),
      ),
    );
  }
}

class GaugeChart extends StatelessWidget {
  const GaugeChart({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.width,
    this.title,
    this.color,
    this.valueFormatter,
    this.theme = const ChartThemeData(),
  });

  final double value;
  final double min;
  final double max;
  final int? width;
  final String? title;
  final Color? color;
  final String Function(double value)? valueFormatter;
  final ChartThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveWidth(width, constraints, 32);
        return _ChartPanel(
          title: title,
          theme: theme,
          child: _ChartFrameWidget(
            frame: ChartRasterizer.gauge(
              value,
              min: min,
              max: max,
              width: resolvedWidth,
              theme: theme,
              color: color,
              valueFormatter: valueFormatter,
            ),
          ),
        );
      },
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    this.title,
    this.legend = const <_LegendEntry>[],
    required this.theme,
    required this.child,
  });

  final String? title;
  final List<_LegendEntry> legend;
  final ChartThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null)
          Text(
            title!,
            style: TextStyle(
              color: theme.valueColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        child,
        if (legend.isNotEmpty)
          RichText(
            softWrap: true,
            text: TextSpan(
              children: <InlineSpan>[
                for (var index = 0;
                    index < legend.length;
                    index++) ...<InlineSpan>[
                  TextSpan(
                    text: '● ',
                    style: TextStyle(color: legend[index].color),
                  ),
                  TextSpan(
                    text: legend[index].label,
                    style: TextStyle(color: theme.labelColor),
                  ),
                  if (index != legend.length - 1) const TextSpan(text: '  '),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartFrameWidget extends StatelessWidget {
  const _ChartFrameWidget({required this.frame});

  final ChartFrame frame;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final row in frame.rows)
          RichText(
            softWrap: false,
            maxLines: 1,
            text: TextSpan(children: _spansForRow(row)),
          ),
      ],
    );
  }

  List<InlineSpan> _spansForRow(List<ChartCell> row) {
    if (row.isEmpty) return const <InlineSpan>[TextSpan(text: '')];
    final spans = <InlineSpan>[];
    var buffer = StringBuffer();
    var currentColor = row.first.color;
    var currentBackground = row.first.backgroundColor;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            color: currentColor,
            backgroundColor: currentBackground,
          ),
        ),
      );
      buffer = StringBuffer();
    }

    for (final cell in row) {
      if (cell.color != currentColor ||
          cell.backgroundColor != currentBackground) {
        flush();
        currentColor = cell.color;
        currentBackground = cell.backgroundColor;
      }
      buffer.write(cell.character);
    }
    flush();
    return spans;
  }
}

final class _ChartBounds {
  const _ChartBounds(this.minX, this.maxX, this.minY, this.maxY);

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

final class _RasterPoint {
  const _RasterPoint(this.x, this.y);

  final int x;
  final int y;
}

final class _BrailleCell {
  int mask = 0;
  Color? color;
}

final class _BrailleCanvas {
  _BrailleCanvas(this.width, this.height)
      : _cells = List<List<_BrailleCell>>.generate(
          height,
          (_) => List<_BrailleCell>.generate(width, (_) => _BrailleCell()),
        );

  final int width;
  final int height;
  final List<List<_BrailleCell>> _cells;

  static const List<List<int>> _dotMasks = <List<int>>[
    <int>[0x01, 0x08],
    <int>[0x02, 0x10],
    <int>[0x04, 0x20],
    <int>[0x40, 0x80],
  ];

  void set(int x, int y, Color color) {
    if (x < 0 || y < 0 || x >= width * 2 || y >= height * 4) return;
    final cell = _cells[y ~/ 4][x ~/ 2];
    cell.mask |= _dotMasks[y % 4][x % 2];
    cell.color = color;
  }

  void drawLine(_RasterPoint start, _RasterPoint end, Color color) {
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
      set(x0, y0, color);
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
  }

  _BrailleCell? cellAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return _cells[y][x];
  }
}

final class _LegendEntry {
  const _LegendEntry(this.label, this.color);

  final String label;
  final Color color;
}

List<_LegendEntry> _legendEntries(
  List<ChartSeries> series,
  ChartThemeData theme,
) {
  return <_LegendEntry>[
    for (var index = 0; index < series.length; index++)
      _LegendEntry(
        series[index].name,
        series[index].color ?? theme.seriesColor(index),
      ),
  ];
}

int _resolveWidth(int? width, BoxConstraints constraints, int fallback) {
  if (width != null) return math.max(1, width);
  if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite) {
    return math.max(1, constraints.maxWidth.floor());
  }
  return fallback;
}

String _fitLabel(String value, int width) {
  if (width <= 0) return '';
  if (value.length == width) return value;
  if (value.length < width) return value.padRight(width);
  if (width == 1) return value.substring(0, 1);
  return '${value.substring(0, width - 1)}…';
}

String _defaultNumberFormat(double value) {
  final absolute = value.abs();
  if (absolute >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (absolute >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (absolute >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

final class _GraphPosition {
  const _GraphPosition(this.x, this.y);

  final int x;
  final int y;
}
