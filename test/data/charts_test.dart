import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('sparkline rasterizer produces a fixed width frame', () {
    final frame = ChartRasterizer.sparkline(<num>[1, 2, 3, 2, 5], width: 12);
    expect(frame.width, 12);
    expect(frame.height, 1);
    expect(frame.toPlainText().trim().length, greaterThan(0));
  });

  test('line chart rasterizer uses braille cells for dense plotting', () {
    final frame = ChartRasterizer.line(
      <ChartSeries>[
        ChartSeries.values(name: 'requests', values: <num>[1, 3, 2, 6, 5]),
      ],
      width: 32,
      height: 10,
    );
    expect(frame.width, 32);
    expect(frame.height, 10);
    expect(
      frame.toPlainText().runes.any((rune) => rune >= 0x2800 && rune <= 0x28ff),
      isTrue,
    );
  });

  test('bar, heatmap, donut and gauge frames are deterministic', () {
    final bars = ChartRasterizer.horizontalBars(
      const <ChartBar>[
        ChartBar(label: 'API', value: 80),
        ChartBar(label: 'Web', value: 45),
      ],
      width: 30,
    );
    final heatmap = ChartRasterizer.heatmap(
      const <List<num>>[
        <num>[0, 1, 2],
        <num>[3, 4, 5],
      ],
    );
    final donut = ChartRasterizer.donut(
      const <ChartBar>[
        ChartBar(label: 'Used', value: 70),
        ChartBar(label: 'Free', value: 30),
      ],
      width: 20,
      height: 10,
    );
    final gauge = ChartRasterizer.gauge(72, width: 24);

    expect(bars.toPlainText(), contains('API'));
    expect(heatmap.width, 3);
    expect(donut.toPlainText().trim().length, greaterThan(0));
    expect(gauge.toPlainText(), contains('72'));
  });

  test('network graph renders labeled nodes and directed edges', () {
    final frame = ChartRasterizer.networkGraph(
      const <GraphNode>[
        GraphNode(id: 'api', label: 'API'),
        GraphNode(id: 'db', label: 'DB'),
        GraphNode(id: 'cache', label: 'Cache'),
      ],
      const <GraphEdge>[
        GraphEdge(from: 'api', to: 'db', directed: true),
        GraphEdge(from: 'api', to: 'cache', directed: true),
      ],
      width: 36,
      height: 12,
    );
    expect(frame.toPlainText(), contains('[API]'));
    expect(frame.toPlainText(), contains('[DB]'));
  });

  test('chart widgets render into the virtual terminal', () async {
    await testCinder('line chart widget', (tester) async {
      await tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 12,
          child: LineChart(
            series: <ChartSeries>[
              ChartSeries.values(
                name: 'Latency',
                values: <num>[12, 18, 15, 24, 20],
              ),
            ],
            title: 'Latency',
          ),
        ),
      );
      expect(tester.terminalState, containsText('Latency'));
    });
  });
}
