import 'dart:async';

import 'package:cinder/cinder.dart';

enum BrowserLabKind {
  gesture,
  hover,
  infiniteList,
  logger,
  mouse,
  resize,
  resizeHistory,
  textField,
}

void runBrowserLab(BrowserLabKind kind) {
  runApp(BrowserLab(kind: kind));
}

class BrowserLab extends StatefulWidget {
  const BrowserLab({super.key, required this.kind});

  final BrowserLabKind kind;

  @override
  State<BrowserLab> createState() => _BrowserLabState();
}

class _BrowserLabState extends State<BrowserLab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _events = <String>[];
  Timer? _timer;
  int _tick = 0;
  int _tapCount = 0;
  bool _hovering = false;
  Size? _lastSize;
  String _submittedText = 'Nothing submitted yet.';

  @override
  void initState() {
    super.initState();
    if (widget.kind == BrowserLabKind.logger) {
      _events.add('logger adapter started');
      _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
        if (!mounted) return;
        setState(() {
          _tick++;
          _events.insert(0, 'INFO frame heartbeat #$_tick');
          if (_events.length > 40) _events.removeLast();
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _record(String event) {
    setState(() {
      _events.insert(0, event);
      if (_events.length > 20) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.kind) {
      case BrowserLabKind.gesture:
        return _buildGestureLab();
      case BrowserLabKind.hover:
        return _buildHoverLab();
      case BrowserLabKind.infiniteList:
        return _buildInfiniteList();
      case BrowserLabKind.logger:
        return _buildLoggerLab();
      case BrowserLabKind.mouse:
        return _buildMouseLab();
      case BrowserLabKind.resize:
        return _buildResizeLab(history: false);
      case BrowserLabKind.resizeHistory:
        return _buildResizeLab(history: true);
      case BrowserLabKind.textField:
        return _buildTextFieldLab();
    }
  }

  Widget _shell({
    required String title,
    required String status,
    required Widget child,
    String footer = 'Rendered by Cinder through WebBackend.',
  }) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.magenta)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ' $title ',
                style: const TextStyle(
                  color: Colors.magenta,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(status, style: const TextStyle(color: Colors.green)),
            ],
          ),
          const SizedBox(height: 1),
          Expanded(child: child),
          const SizedBox(height: 1),
          Text(footer, style: const TextStyle(color: Colors.gray)),
        ],
      ),
    );
  }

  Widget _buildGestureLab() {
    return _shell(
      title: 'GESTURE DETECTOR / WEB ADAPTER',
      status: 'MOUSE EVENTS ACTIVE',
      footer: 'Click, double-click, or hold the interaction zone.',
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                _tapCount++;
                _record('tap #$_tapCount');
              },
              onDoubleTap: () => _record('double tap'),
              onLongPress: () => _record('long press'),
              child: Container(
                decoration: BoxDecoration(
                  border: BoxBorder.all(color: Colors.cyan),
                  color: const Color.fromRGB(15, 22, 32),
                ),
                child: Center(
                  child: Text(
                    _tapCount == 0 ? 'INTERACT HERE' : 'TAPS: $_tapCount',
                    style: const TextStyle(
                      color: Colors.cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(height: 9, child: _eventLedger('GESTURE EVENT LEDGER')),
        ],
      ),
    );
  }

  Widget _buildHoverLab() {
    return _shell(
      title: 'HOVERABLE WIDGETS / WEB ADAPTER',
      status: _hovering ? 'POINTER INSIDE' : 'WAITING',
      footer: 'Move the pointer across the rows; click to record activation.',
      child: ListView.builder(
        controller: _scrollController,
        itemCount: 18,
        itemBuilder: (context, index) {
          return MouseRegion(
            onEnter: (_) {
              setState(() => _hovering = true);
              _record('entered row ${index + 1}');
            },
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              onTap: () => _record('activated row ${index + 1}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  border: BoxBorder(
                    bottom: BorderSide(color: Colors.gray.withOpacity(0.35)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ROW ${(index + 1).toString().padLeft(2, '0')}'),
                    const Text(
                      'hover / click',
                      style: TextStyle(color: Colors.cyan),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfiniteList() {
    return _shell(
      title: 'INFINITE LIST / WEB ADAPTER',
      status: 'VIRTUAL BUILDER',
      footer: 'Scroll with the wheel or arrow keys. Rows are created lazily.',
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: 10000,
          itemBuilder: (context, index) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: BoxBorder(
                  bottom: BorderSide(color: Colors.gray.withOpacity(0.22)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('item ${(index + 1).toString().padLeft(5, '0')}'),
                  Text(
                    index.isEven ? 'even' : 'odd',
                    style: TextStyle(
                      color: index.isEven ? Colors.cyan : Colors.yellow,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoggerLab() {
    return _shell(
      title: 'LOGGER / WEB ADAPTER',
      status: '$_tick EVENTS',
      footer: 'The browser adapter writes to a deterministic in-memory ledger.',
      child: _eventLedger('LIVE LOG STREAM'),
    );
  }

  Widget _buildMouseLab() {
    return _shell(
      title: 'MOUSE INPUT / WEB ADAPTER',
      status: _hovering ? 'TRACKING' : 'IDLE',
      footer: 'Pointer events pass from xterm.js into Cinder hit testing.',
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovering = true);
          _record('pointer entered canvas');
        },
        onExit: (_) {
          setState(() => _hovering = false);
          _record('pointer exited canvas');
        },
        onHover: (event) => _record('hover ${event.x},${event.y}'),
        child: GestureDetector(
          onTap: () => _record('primary click'),
          child: Container(
            decoration: BoxDecoration(
              border: BoxBorder.all(
                color: _hovering ? Colors.yellow : Colors.cyan,
              ),
            ),
            child: Center(
              child: Text(
                _hovering ? 'POINTER DETECTED' : 'MOVE POINTER HERE',
                style: TextStyle(
                  color: _hovering ? Colors.yellow : Colors.cyan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResizeLab({required bool history}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize != size) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _lastSize == size) return;
            setState(() {
              _lastSize = size;
              if (history) {
                _events.insert(
                  0,
                  '${size.width.toInt()}×${size.height.toInt()}',
                );
                if (_events.length > 12) _events.removeLast();
              }
            });
          });
        }

        return _shell(
          title: history
              ? 'RESIZE EVENT LEDGER / WEB ADAPTER'
              : 'TERMINAL RESIZE / WEB ADAPTER',
          status: '${size.width.toInt()}×${size.height.toInt()}',
          footer:
              'Resize the browser frame; Cinder receives new cell constraints.',
          child: history
              ? _eventLedger('RECENT CELL GEOMETRY')
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${size.width.toInt()} columns',
                        style: const TextStyle(
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('${size.height.toInt()} rows'),
                      const SizedBox(height: 1),
                      const Text('LayoutBuilder is live.'),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTextFieldLab() {
    return _shell(
      title: 'TEXT FIELD / WEB ADAPTER',
      status: 'UNICODE READY',
      footer:
          'Try Cyrillic, Arabic, CJK, emoji, combining marks, and navigation keys.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Input', style: TextStyle(color: Colors.cyan)),
          TextField(
            controller: _textController,
            autofocus: true,
            placeholder: 'Type text and press Enter…',
            onSubmitted: (value) {
              setState(() {
                _submittedText = value.isEmpty ? '(empty)' : value;
                _events.insert(0, _submittedText);
                _textController.clear();
              });
            },
          ),
          const SizedBox(height: 1),
          const Text('Last submitted', style: TextStyle(color: Colors.cyan)),
          Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: BoxBorder.all(color: Colors.gray),
            ),
            child: Text(_submittedText),
          ),
          const SizedBox(height: 1),
          Expanded(child: _eventLedger('SUBMISSION HISTORY')),
        ],
      ),
    );
  }

  Widget _eventLedger(String title) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.gray)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.cyan)),
          const SizedBox(height: 1),
          Expanded(
            child: ListView(
              children:
                  (_events.isEmpty ? const <String>['No events yet.'] : _events)
                      .map((event) => Text('› $event'))
                      .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}
