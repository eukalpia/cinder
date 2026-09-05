/// Large-data operations console. See doc/scale-monitor.md for stress runs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:cinder/cinder.dart';

/// Immutable archive and live records share bounded, deterministic text fields.
class ScaleRecord {
  const ScaleRecord(this.id);

  final int id;
  String get service =>
      const ['gateway', 'payment', 'search', 'worker'][id % 4];
  String get level => id % 17 == 0 ? 'ERROR' : (id % 5 == 0 ? 'WARN' : 'INFO');
  String get message => const [
    '東京 request completed 🚀',
    'Payment accepted · café',
    'Index refreshed · Привет',
    'Job completed · مرحبا',
  ][id % 4];

  bool matches(String query) =>
      service.contains(query) ||
      level.toLowerCase().contains(query) ||
      message.toLowerCase().contains(query) ||
      id.toString().contains(query);
}

/// Owns one archive, one ring, one active search, and one pending query.
/// Rendering never filters, sorts or copies the archive.
class ScaleMonitorModel extends Listenable {
  ScaleMonitorModel({this.recordCount = 100000, this.historyLimit = 2048}) {
    if (recordCount < 1 || recordCount > 10000000) {
      throw ArgumentError.value(
        recordCount,
        'recordCount',
        'must be 1..10000000',
      );
    }
    if (historyLimit < 1 || historyLimit > 1000000) {
      throw ArgumentError.value(
        historyLimit,
        'historyLimit',
        'must be 1..1000000',
      );
    }
    _archive = List.generate(recordCount, ScaleRecord.new, growable: false);
    _ring = List<ScaleRecord?>.filled(historyLimit, null);
  }

  static const queryLimit = 256;
  static const searchBatchSize = 512;
  final int recordCount;
  final int historyLimit;
  final _tasks = CinderTaskScope(historyLimit: 8);
  final _listeners = <VoidCallback>{};
  late List<ScaleRecord> _archive;
  late List<ScaleRecord?> _ring;
  Uint32List? _matches;
  int _matchCount = 0;
  int _liveStart = 0;
  int _liveCount = 0;
  int _revision = 0;
  String? _pendingQuery;
  CinderTask<void>? _searchTask;
  Future<void> _searchSettled = Future<void>.value();
  Future<void>? _disposal;
  Timer? _producer;
  Duration _streamInterval = const Duration(milliseconds: 50);
  int _streamBurst = 64;
  bool _notificationScheduled = false;
  bool _disposed = false;
  bool _showLive = false;
  int _selectedIndex = 0;
  String query = '';
  String appliedQuery = '';
  int ingestedRecords = 0;
  int droppedRecords = 0;
  int notificationCount = 0;
  int rowBuildCount = 0;
  int widgetBuildCount = 0;
  int handledKeyCount = 0;
  int searchRecordsExamined = 0;
  int searchCompletedCount = 0;
  int searchCancelledCount = 0;
  int maxActiveSearchCount = 0;
  int viewportWidth = 0;
  int viewportHeight = 0;
  int frameCount = 0;
  int frameTotalMicros = 0;
  int frameMaxMicros = 0;
  int maxRowsPerFrame = 0;
  int _previousRowBuildCount = 0;
  final List<int> frameHistogram = List.filled(9, 0);
  static const frameBucketsMicros = [
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
    33000,
  ];
  int lastSearchMicros = 0;
  int maxSearchMicros = 0;

  bool get isDisposed => _disposed;
  bool get isStreaming => _producer?.isActive ?? false;
  bool get showLive => _showLive;
  int get liveCount => _liveCount;
  int get retainedArchiveCount => _archive.length;
  int get selectedIndex => _selectedIndex;
  int get visibleCount => _showLive
      ? _liveCount
      : (_matches == null ? _archive.length : _matchCount);
  int get activeSearchCount => _searchTask == null ? 0 : 1;
  int get pendingSearchCount => _pendingQuery == null ? 0 : 1;
  Future<void> get searchSettled => _searchSettled;
  ScaleRecord? get selectedRecord =>
      visibleCount == 0 ? null : recordAt(_selectedIndex);

  ScaleRecord liveRecordAt(int index) {
    RangeError.checkValidIndex(index, _ring, 'index', _liveCount);
    return _ring[(_liveStart + index) % historyLimit]!;
  }

  ScaleRecord recordAt(int index) {
    if (_showLive) return liveRecordAt(index);
    RangeError.checkValidIndex(index, _archive, 'index', visibleCount);
    return _archive[_matches == null ? index : _matches![index]];
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_disposed) _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    if (_disposed || _notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (_disposed) return;
      notificationCount++;
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    });
  }

  /// Truncate before normalizing: even adversarial paste has bounded retained
  /// text and query-normalization work. Do not split UTF-16 surrogate pairs.
  static String boundedQuery(String value) {
    if (value.length <= queryLimit) return value;
    var end = queryLimit;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xd800 && last <= 0xdbff) end--;
    return value.substring(0, end);
  }

  Future<void> search(String text) {
    if (_disposed) return Future<void>.value();
    query = boundedQuery(text);
    _pendingQuery = query.trim().toLowerCase();
    _revision++;
    _notify();
    // Superseding requests replace one string; they never start another task.
    if (_searchTask != null) return _searchSettled;
    _searchTask = _tasks.run<void>(_drainSearches, label: 'archive search');
    maxActiveSearchCount = 1;
    _searchSettled = _searchTask!.future.whenComplete(() {
      _searchTask = null;
      // A completion notification may submit another query before the task's
      // Future finishes unwinding. Keep the original waiter attached to it.
      final pending = _pendingQuery;
      if (pending != null && !_disposed) return search(pending);
      _notify();
    });
    return _searchSettled;
  }

  Future<void> _drainSearches(CancellationToken token) async {
    // Yield before reading the pending slot, coalescing a synchronous key burst.
    await Future<void>.delayed(Duration.zero);
    while (_pendingQuery != null && !_disposed && !token.isCancelled) {
      final nextQuery = _pendingQuery!;
      _pendingQuery = null;
      final revision = _revision;
      final watch = Stopwatch()..start();
      final indices = nextQuery.isEmpty ? null : Uint32List(_archive.length);
      var found = 0;
      if (indices != null) {
        for (var start = 0; start < _archive.length; start += searchBatchSize) {
          final end = (start + searchBatchSize).clamp(0, _archive.length);
          for (var index = start; index < end; index++) {
            searchRecordsExamined++;
            if (_archive[index].matches(nextQuery)) indices[found++] = index;
          }
          await Future<void>.delayed(Duration.zero);
          if (token.isCancelled || _disposed || revision != _revision) break;
        }
      }
      if (token.isCancelled || _disposed || revision != _revision) {
        searchCancelledCount++;
        continue;
      }
      _matches = indices;
      _matchCount = found;
      appliedQuery = nextQuery;
      _showLive = false;
      _selectedIndex = 0;
      lastSearchMicros = watch.elapsedMicroseconds;
      if (lastSearchMicros > maxSearchMicros) {
        maxSearchMicros = lastSearchMicros;
      }
      searchCompletedCount++;
      _notify();
      // Deliver the completion notification before deciding the worker is idle.
      await Future<void>.delayed(Duration.zero);
    }
  }

  void cancelSearch() {
    if (_pendingQuery != null) searchCancelledCount++;
    _pendingQuery = null;
    _revision++;
    _notify();
  }

  void ingest(int count) {
    if (_disposed || count <= 0) return;
    for (var i = 0; i < count; i++) {
      final record = ScaleRecord(recordCount + ingestedRecords++);
      if (_liveCount == historyLimit) {
        _ring[_liveStart] = record;
        _liveStart = (_liveStart + 1) % historyLimit;
        droppedRecords++;
      } else {
        _ring[(_liveStart + _liveCount++) % historyLimit] = record;
      }
    }
    if (_showLive && _liveCount > 0) _selectedIndex = _liveCount - 1;
    _notify();
  }

  void startStreaming({Duration? interval, int? burst}) {
    if (_disposed || isStreaming) return;
    interval ??= _streamInterval;
    burst ??= _streamBurst;
    if (interval <= Duration.zero || burst < 1 || burst > 100000) {
      throw ArgumentError(
        'stream interval must be positive and burst 1..100000',
      );
    }
    _streamInterval = interval;
    _streamBurst = burst;
    _producer = Timer.periodic(interval, (_) => ingest(_streamBurst));
    _notify();
  }

  void stopStreaming() {
    _producer?.cancel();
    _producer = null;
    _notify();
  }

  void toggleLive() {
    _showLive = !_showLive;
    _selectedIndex = _showLive && _liveCount > 0 ? _liveCount - 1 : 0;
    _notify();
  }

  void select(int index) {
    if (visibleCount == 0) return;
    _selectedIndex = index.clamp(0, visibleCount - 1);
    _notify();
  }

  void recordFrame(FrameTiming timing) {
    final micros = timing.totalDuration.inMicroseconds;
    frameCount++;
    frameTotalMicros += micros;
    if (micros > frameMaxMicros) frameMaxMicros = micros;
    final rows = rowBuildCount - _previousRowBuildCount;
    _previousRowBuildCount = rowBuildCount;
    if (rows > maxRowsPerFrame) maxRowsPerFrame = rows;
    var bucket = 0;
    while (bucket < frameBucketsMicros.length &&
        micros > frameBucketsMicros[bucket]) {
      bucket++;
    }
    frameHistogram[bucket]++;
  }

  Map<String, Object?> metrics() => {
    'records': recordCount,
    'retained_archive': retainedArchiveCount,
    'live_records': liveCount,
    'history_limit': historyLimit,
    'ingested_records': ingestedRecords,
    'dropped_records': droppedRecords,
    'query_code_units': query.length,
    'query': query,
    'applied_query': appliedQuery,
    'visible_records': visibleCount,
    'selected_id': selectedRecord?.id,
    'show_live': showLive,
    'streaming': isStreaming,
    'active_searches': activeSearchCount,
    'pending_searches': pendingSearchCount,
    'task_history': _tasks.history.length,
    'row_builds': rowBuildCount,
    'frames': frameCount,
    'frame_total_us': frameTotalMicros,
    'frame_max_us': frameMaxMicros,
    'max_rows_per_frame': maxRowsPerFrame,
    'frame_bucket_limits_us': frameBucketsMicros,
    'frame_histogram': frameHistogram,
    'widget_builds': widgetBuildCount,
    'notifications': notificationCount,
    'handled_keys': handledKeyCount,
    'search_records_examined': searchRecordsExamined,
    'search_completed': searchCompletedCount,
    'search_cancelled': searchCancelledCount,
    'last_search_us': lastSearchMicros,
    'max_search_us': maxSearchMicros,
    'width': viewportWidth,
    'height': viewportHeight,
    'disposed': isDisposed,
  };

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _disposed = true;
    _producer?.cancel();
    _producer = null;
    _pendingQuery = null;
    _revision++;
    _listeners.clear();
    _disposal = _finishDisposal();
    return _disposal!;
  }

  Future<void> _finishDisposal() async {
    await _tasks.dispose();
    await _searchSettled;
    _archive = [];
    _ring = [];
    _matches = null;
    _liveCount = _matchCount = 0;
  }
}

/// The widget owns its model's lifecycle, including stream and search shutdown.
class ScaleMonitor extends StatefulWidget {
  const ScaleMonitor({super.key, required this.model, this.onDisposed});
  final ScaleMonitorModel model;
  final VoidCallback? onDisposed;

  @override
  State<ScaleMonitor> createState() => _ScaleMonitorState();
}

class _ScaleMonitorState extends State<ScaleMonitor> {
  final _scroll = ScrollController();
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  int _lastSearchCompleted = 0;

  ScaleMonitorModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    SchedulerBinding.instance.addFrameTimingCallback(model.recordFrame);
  }

  void _changed() {
    if (!mounted) return;
    if (_lastSearchCompleted != model.searchCompletedCount) {
      _lastSearchCompleted = model.searchCompletedCount;
      _scroll.scrollToStart();
    } else if (model.showLive) {
      _scroll.scrollToEnd();
    }
    setState(() {});
  }

  void _select(int index) {
    model.select(index);
    _scroll.ensureIndexVisible(index: model.selectedIndex);
  }

  bool _key(KeyboardEvent event) {
    if (event.isUp) return false;
    final key = event.logicalKey;
    if (key == LogicalKey.escape) {
      _searchFocus.unfocus();
      model.cancelSearch();
    } else if (_searchFocus.hasFocus) {
      return false;
    } else if (key == LogicalKey.slash) {
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
      _searchFocus.requestFocus();
    } else if (key == LogicalKey.keyQ) {
      shutdownApp();
    } else if (key == LogicalKey.keyL) {
      model.toggleLive();
      if (model.showLive) {
        _scroll.scrollToEnd();
      } else {
        _scroll.scrollToStart();
      }
    } else if (key == LogicalKey.keyP) {
      model.isStreaming ? model.stopStreaming() : model.startStreaming();
    } else if (key == LogicalKey.home) {
      _select(0);
    } else if (key == LogicalKey.end) {
      _select(model.visibleCount - 1);
    } else if (key == LogicalKey.arrowDown) {
      _select(model.selectedIndex + 1);
    } else if (key == LogicalKey.arrowUp) {
      _select(model.selectedIndex - 1);
    } else if (key == LogicalKey.pageDown) {
      _select(model.selectedIndex + (model.viewportHeight - 5).clamp(1, 1000));
    } else if (key == LogicalKey.pageUp) {
      _select(model.selectedIndex - (model.viewportHeight - 5).clamp(1, 1000));
    } else {
      return false;
    }
    model.handledKeyCount++;
    return true;
  }

  bool _searchKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) return _key(event);
    if (event.isUp) return true;
    final text = event.character;
    if (text == null ||
        event.logicalKey == LogicalKey.enter ||
        event.logicalKey == LogicalKey.backspace ||
        event.logicalKey == LogicalKey.tab ||
        event.modifiers.hasAnyModifier) {
      return false;
    }
    final selection = _query.selection;
    final retained = _query.text.length - (selection.end - selection.start);
    if (retained + text.length <= ScaleMonitorModel.queryLimit) return false;
    final prefix = _query.text.substring(0, selection.start);
    final suffix = _query.text.substring(selection.end);
    _query.text = ScaleMonitorModel.boundedQuery(
      '$prefix${ScaleMonitorModel.boundedQuery(text)}$suffix',
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    model.widgetBuildCount++;
    return Focusable(
      focused: true,
      onKeyEvent: _key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          model.viewportWidth = constraints.maxWidth.toInt();
          model.viewportHeight = constraints.maxHeight.toInt();
          if (constraints.maxHeight < 6) {
            return const Text('Enlarge terminal · q quits', maxLines: 1);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CINDER OPS  ${model.showLive ? 'LIVE' : 'ARCHIVE'}  ${model.visibleCount} records',
                style: const TextStyle(
                  color: Colors.cyan,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
              SizedBox(
                height: 1,
                child: TextField(
                  controller: _query,
                  focusNode: _searchFocus,
                  maxLength: ScaleMonitorModel.queryLimit,
                  placeholder: '/ search archive · Enter applies · Esc cancels',
                  onPaste: (text) {
                    _query.text = ScaleMonitorModel.boundedQuery(text);
                    return true;
                  },
                  onKeyEvent: _searchKey,
                  onSubmitted: (text) {
                    _searchFocus.unfocus();
                    unawaited(model.search(text));
                  },
                ),
              ),
              const Text('     ID  LEVEL  SERVICE     MESSAGE', maxLines: 1),
              Expanded(
                child: model.visibleCount == 0
                    ? const Text('No matching records', maxLines: 1)
                    : ListView.builder(
                        lazy: true,
                        itemExtent: 1,
                        cacheExtent: 2,
                        controller: _scroll,
                        itemCount: model.visibleCount,
                        itemBuilder: (context, index) {
                          model.rowBuildCount++;
                          return ScaleLogRow(
                            record: model.recordAt(index),
                            selected: index == model.selectedIndex,
                            onSelect: () => _select(index),
                          );
                        },
                      ),
              ),
              Text(
                '${model.isStreaming ? 'streaming' : 'paused'}  live ${model.liveCount}/${model.historyLimit}  '
                'evicted ${model.droppedRecords}  ${model.activeSearchCount > 0 ? 'searching…' : 'ready'}  '
                'selected ${model.selectedRecord?.id ?? '—'}',
                maxLines: 1,
              ),
              const Text(
                '↑↓ PgUp/PgDn Home/End select · / search · l live/archive · p pause · q quit',
                maxLines: 1,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    SchedulerBinding.instance.removeFrameTimingCallback(model.recordFrame);
    _scroll.dispose();
    _query.dispose();
    _searchFocus.dispose();
    final onDisposed = widget.onDisposed;
    unawaited(model.dispose().then((_) => onDisposed?.call()));
    super.dispose();
  }
}

class ScaleLogRow extends StatelessWidget {
  const ScaleLogRow({
    super.key,
    required this.record,
    required this.selected,
    required this.onSelect,
  });
  final ScaleRecord record;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onSelect,
    child: Text(
      '${selected ? '›' : ' '} ${record.id.toString().padLeft(6)}  ${record.level.padRight(5)}  '
      '${record.service.padRight(10)}  ${record.message}',
      style: TextStyle(
        color: selected ? Colors.black : Colors.white,
        backgroundColor: selected ? Colors.cyan : null,
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
    ),
  );
}

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln(
      'dart run example/scale_monitor.dart [--records=100000] [--history=2048] '
      '[--burst=64] [--duration=0] [--metrics=/path/run.jsonl] [--diagnostic]',
    );
    return;
  }
  String? option(String name) {
    for (final arg in args) {
      if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
    }
    return null;
  }

  final model = ScaleMonitorModel(
    recordCount: int.parse(option('records') ?? '100000'),
    historyLimit: int.parse(option('history') ?? '2048'),
  );
  final metricsPath = option('metrics');
  final duration = int.parse(option('duration') ?? '0');
  final resources = CinderResourceScope();
  final watch = Stopwatch()..start();
  final diagnostic = args.contains('--diagnostic');
  String? serviceUri;
  if (diagnostic) {
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw ArgumentError(
        '--diagnostic requires JIT; use AOT for RSS measurement',
      );
    }
    final service = await developer.Service.controlWebServer(enable: true);
    serviceUri = service.serverUri?.toString();
  }
  RandomAccessFile? metrics;
  if (metricsPath != null) {
    metrics = File(metricsPath).openSync(mode: FileMode.write);
    resources.add(metrics.close);
  }
  var frameworkErrors = 0;
  final previousErrorHandler = CinderError.onError;
  CinderError.onError = (details) {
    frameworkErrors++;
    previousErrorHandler?.call(details);
  };
  resources.add(() => CinderError.onError = previousErrorHandler);
  var samples = 0;
  void sample(String event) {
    final snapshot = {
      'event': event,
      'sample': samples++,
      'elapsed_ms': watch.elapsedMilliseconds,
      'pid': pid,
      'runtime': const bool.fromEnvironment('dart.vm.product') ? 'aot' : 'jit',
      'diagnostic': diagnostic,
      'dart_version': Platform.version,
      'source_sha256': const String.fromEnvironment(
        'scale.source_hash',
        defaultValue: 'unrecorded',
      ),
      'rss_bytes': ProcessInfo.currentRss,
      'max_rss_bytes': ProcessInfo.maxRss,
      'vm_service_uri': serviceUri,
      'framework_errors': frameworkErrors,
      ...model.metrics(),
    };
    // One bounded synchronous JSON line per second: no metrics queue accumulates
    // if the destination slows down. Timing samples include this I/O overhead.
    metrics?.writeStringSync('${jsonEncode(snapshot)}\n');
  }

  model.startStreaming(burst: int.parse(option('burst') ?? '64'));
  sample('start');
  if (metrics != null) {
    resources.trackTimer(
      Timer.periodic(const Duration(seconds: 1), (_) => sample('sample')),
    );
  }
  if (duration > 0) {
    resources.trackTimer(Timer(Duration(seconds: duration), shutdownApp));
  }
  await runApp(
    ScaleMonitor(
      model: model,
      onDisposed: () {
        sample('disposed');
        resources.disposeDetached();
      },
    ),
    enableHotReload: false,
  );
  await model.dispose();
  await resources.dispose();
}
