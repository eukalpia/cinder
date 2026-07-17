import 'dart:math' as math;

import 'package:cinder/cinder.dart';

class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.width});

  final List<num> values;
  final int? width;

  @override
  Widget build(BuildContext context) => Text(render());

  String render() {
    if (values.isEmpty) return '';
    final sampled = _sample(values, width ?? values.length);
    final minimum = sampled.reduce(math.min).toDouble();
    final maximum = sampled.reduce(math.max).toDouble();
    const blocks = '▁▂▃▄▅▆▇█';
    final range = maximum - minimum;
    return sampled.map((value) {
      final level = range == 0
          ? 0
          : (((value - minimum) / range) * (blocks.length - 1)).round();
      return blocks[level];
    }).join();
  }
}

class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    this.labels = const <String>[],
    this.width = 40,
    this.showValues = true,
  });

  final List<num> values;
  final List<String> labels;
  final int width;
  final bool showValues;

  @override
  Widget build(BuildContext context) => Text(render());

  String render() {
    if (values.isEmpty) return '';
    final maximum = values
        .map((value) => value.abs())
        .fold<double>(0, math.max);
    final labelWidth = labels.isEmpty
        ? 0
        : labels.fold<int>(
            0,
            (current, label) => math.max(current, label.length),
          );
    return List<String>.generate(values.length, (index) {
      final value = values[index].toDouble();
      final count = maximum == 0 ? 0 : (value.abs() / maximum * width).round();
      final label = index < labels.length
          ? labels[index].padRight(labelWidth)
          : '';
      return '${label.isEmpty ? '' : '$label │'}'
          '${value < 0 ? '◀' : '▶'}${'█' * count}'
          '${showValues ? ' $value' : ''}';
    }).join('\n');
  }
}

class LineChart extends StatelessWidget {
  const LineChart(this.values, {super.key, this.width = 60, this.height = 12});

  final List<num> values;
  final int width;
  final int height;

  @override
  Widget build(BuildContext context) => Text(render());

  String render() {
    if (values.isEmpty || width <= 0 || height <= 0) return '';
    final sampled = _sample(values, width);
    final minimum = sampled.reduce(math.min).toDouble();
    final maximum = sampled.reduce(math.max).toDouble();
    final range = maximum - minimum;
    final grid = List<List<String>>.generate(
      height,
      (_) => List<String>.filled(width, ' '),
    );
    for (var x = 0; x < sampled.length; x++) {
      final normalized = range == 0 ? 0.5 : (sampled[x] - minimum) / range;
      final y = (height - 1 - normalized * (height - 1)).round().clamp(
        0,
        height - 1,
      );
      grid[y][x] = '●';
      if (x > 0) {
        final previous = grid.indexWhere((row) => row[x - 1] == '●');
        if (previous >= 0 && previous != y) {
          final low = math.min(previous, y);
          final high = math.max(previous, y);
          for (var connector = low + 1; connector < high; connector++) {
            grid[connector][x] = '│';
          }
        }
      }
    }
    return grid.map((row) => row.join()).join('\n');
  }
}

List<double> _sample(List<num> values, int count) {
  if (values.length <= count) {
    return values.map((value) => value.toDouble()).toList();
  }
  return List<double>.generate(
    count,
    (index) =>
        values[(index * (values.length - 1) / math.max(1, count - 1)).round()]
            .toDouble(),
  );
}
