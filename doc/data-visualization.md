# Data visualization

Cinder provides terminal-native data visualization without browser, Flutter, or
Node.js dependencies. Charts rasterize into ordinary terminal cells and can be
used in mounted widgets, snapshots, logs, SSH sessions, and plain-text exports.

## Supported visualizations

- line charts with dense Braille plotting;
- scatter plots;
- horizontal and vertical bar charts;
- histograms;
- heatmaps;
- donut charts;
- gauges;
- sparklines;
- network graphs with circular or grid layout.

All visualizations have two layers:

1. `ChartRasterizer` produces an immutable `ChartFrame`;
2. widgets such as `LineChart` and `NetworkGraphChart` integrate the frame into
   layout, themes, legends, and application composition.

This separation makes the output deterministic and testable.

## Line chart

```dart
LineChart(
  title: 'Requests per second',
  series: <ChartSeries>[
    ChartSeries.values(
      name: 'RPS',
      values: <num>[920, 1110, 1080, 1340, 1290],
    ),
  ],
)
```

The line rasterizer uses Unicode Braille cells. One terminal cell therefore
represents an internal 2×4 dot matrix, providing much higher visual resolution
than one-character-per-point rendering.

## Network graph

```dart
NetworkGraphChart(
  nodes: const <GraphNode>[
    GraphNode(id: 'api', label: 'API'),
    GraphNode(id: 'db', label: 'Postgres'),
    GraphNode(id: 'cache', label: 'Cache'),
  ],
  edges: const <GraphEdge>[
    GraphEdge(from: 'api', to: 'db', directed: true),
    GraphEdge(from: 'api', to: 'cache', directed: true),
  ],
)
```

The layout is deterministic, so snapshots and CI output do not change between
runs. Invalid edges whose endpoints are absent are ignored safely.

## Pure rasterization

```dart
final frame = ChartRasterizer.horizontalBars(
  const <ChartBar>[
    ChartBar(label: 'API', value: 82),
    ChartBar(label: 'Search', value: 58),
  ],
  width: 40,
);

stdout.write(frame.toPlainText());
```

A `ChartFrame` contains styled `ChartCell` objects and also exposes
`toPlainText()` for logs and non-interactive output.

## Large datasets

Charts sample ordered series to the available viewport instead of building one
widget per observation. Tabular and hierarchical data should use
`VirtualizedDataTable` and `TreeView`; both are backed by Cinder's lazy list
viewport and only build visible rows plus a configurable cache extent.

## Capability degradation

Charts do not require native terminal image protocols. They work in basic
Unicode terminals and through SSH or tmux. Applications that must support ASCII
only can call the pure rasterizer and transform chart glyphs into an
application-specific fallback representation.
