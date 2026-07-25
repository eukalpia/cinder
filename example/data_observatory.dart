import 'package:cinder/cinder.dart';

void main() {
  runApp(
    const CinderApp(
      title: 'Cinder Data Observatory',
      theme: TuiThemeData.nord,
      child: DataObservatory(),
    ),
  );
}

class DataObservatory extends StatefulWidget {
  const DataObservatory({super.key});

  @override
  State<DataObservatory> createState() => _DataObservatoryState();
}

class _DataObservatoryState extends State<DataObservatory> {
  int selectedTab = 0;

  static const services = <_ServiceRow>[
    _ServiceRow('api', 'healthy', 1842, 38),
    _ServiceRow('payments', 'healthy', 730, 51),
    _ServiceRow('search', 'degraded', 1260, 94),
    _ServiceRow('worker', 'healthy', 408, 27),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Tabs(
        tabs: const <TabItem>[
          TabItem(label: 'Overview'),
          TabItem(label: 'Topology'),
          TabItem(label: 'Services'),
        ],
        selectedIndex: selectedTab,
        onSelected: (index) => setState(() => selectedTab = index),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: LineChart(
                  title: 'Requests per second',
                  height: 14,
                  series: <ChartSeries>[
                    ChartSeries.values(
                      name: 'RPS',
                      values: const <num>[
                        920,
                        1110,
                        1080,
                        1340,
                        1290,
                        1510,
                        1640
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    GaugeChart(
                      title: 'CPU',
                      value: 63,
                      width: 28,
                    ),
                    SizedBox(height: 1),
                    BarChart(
                      title: 'Traffic by service',
                      width: 30,
                      bars: <ChartBar>[
                        ChartBar(label: 'API', value: 82),
                        ChartBar(label: 'Search', value: 58),
                        ChartBar(label: 'Jobs', value: 34),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const NetworkGraphChart(
            title: 'Runtime topology',
            height: 17,
            nodes: <GraphNode>[
              GraphNode(id: 'gateway', label: 'Gateway'),
              GraphNode(id: 'api', label: 'API'),
              GraphNode(id: 'cache', label: 'Cache'),
              GraphNode(id: 'db', label: 'Postgres'),
              GraphNode(id: 'jobs', label: 'Workers'),
            ],
            edges: <GraphEdge>[
              GraphEdge(from: 'gateway', to: 'api', directed: true),
              GraphEdge(from: 'api', to: 'cache', directed: true),
              GraphEdge(from: 'api', to: 'db', directed: true),
              GraphEdge(from: 'api', to: 'jobs', directed: true),
              GraphEdge(from: 'jobs', to: 'db', directed: true),
            ],
          ),
          VirtualizedDataTable<_ServiceRow>(
            autofocus: true,
            rows: services,
            rowKey: (row) => row.name,
            columns: const <DataColumn<_ServiceRow>>[
              DataColumn<_ServiceRow>(
                label: 'Service',
                width: 20,
                value: _serviceName,
              ),
              DataColumn<_ServiceRow>(
                label: 'Status',
                width: 14,
                value: _serviceStatus,
              ),
              DataColumn<_ServiceRow>(
                label: 'RPS',
                width: 12,
                numeric: true,
                value: _serviceRps,
              ),
              DataColumn<_ServiceRow>(
                label: 'p95 ms',
                width: 12,
                numeric: true,
                value: _serviceLatency,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceRow {
  const _ServiceRow(this.name, this.status, this.rps, this.latency);

  final String name;
  final String status;
  final int rps;
  final int latency;
}

Object? _serviceName(_ServiceRow row) => row.name;
Object? _serviceStatus(_ServiceRow row) => row.status;
Object? _serviceRps(_ServiceRow row) => row.rps;
Object? _serviceLatency(_ServiceRow row) => row.latency;
