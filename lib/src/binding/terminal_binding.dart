import 'dart:async';
import 'dart:convert';

import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:cinder/src/navigation/render_theater.dart';
import 'package:cinder/src/rendering/scrollable_render_object.dart';
import 'package:cinder/src/image/image_cleanup.dart';

import '../backend/terminal.dart' as term;
import '../buffer.dart' as buf;
import '../keyboard/input_parser.dart';
import '../rendering/frame_diff.dart';
import '../rendering/mouse_hit_test.dart';
import '../rendering/mouse_tracker.dart';
import 'hot_reload_mixin.dart';

/// Terminal UI binding that handles terminal input/output and event loop
class TerminalBinding extends CinderBinding
    with SchedulerBinding, HotReloadBinding {
  TerminalBinding(
    this.terminal, {
    TerminalCapabilities? capabilities,
  }) : capabilities = capabilities ??
            TerminalCapabilities.fromEnvironment(
              const <String, String>{},
              stdinHasTerminal: terminal.backend.inputStream != null,
              stdoutHasTerminal: terminal.backend.isAvailable,
            ) {
    _instance = this;
    _initializePipelineOwner();
  }

  static TerminalBinding? _instance;
  static TerminalBinding get instance => _instance!;

  final term.Terminal terminal;

  /// Immutable feature profile selected before terminal initialization.
  final TerminalCapabilities capabilities;

  /// Global normalized input phases that run before widget-tree dispatch.
  final InputRouter inputRouter = InputRouter();

  PipelineOwner? _pipelineOwner;
  PipelineOwner get pipelineOwner => _pipelineOwner!;

  bool _shouldExit = false;

  /// Whether the binding has been signaled to exit
  bool get shouldExit => _shouldExit;

  final _inputController = StreamController<String>.broadcast();
  final _normalizedInputController = StreamController<InputEvent>.broadcast();
  final _keyboardEventController = StreamController<KeyboardEvent>.broadcast();
  final _inputParser = InputParser();
  final _mouseEventController = StreamController<MouseEvent>.broadcast();
  Timer? _escapeResolutionTimer;

  /// Delay used to distinguish a standalone Escape key from a split sequence.
  Duration escapeAmbiguityTimeout = const Duration(milliseconds: 25);

  /// Timestamp of last input bytes added to parser (for buffer staleness detection)
  DateTime? _lastInputTime;

  /// Timeout for stale buffer detection (100ms)
  static const _bufferStaleTimeout = Duration(milliseconds: 100);
  final _mouseTracker = MouseTracker();
  final _oscEventsController = StreamController<String>.broadcast();

  /// Front buffer currently represented by the physical terminal.
  buf.Buffer? _previousBuffer;

  /// Reusable back buffer painted for the next frame.
  buf.Buffer? _nextBuffer;
  buf.Buffer? _pendingFrameBuffer;
  List<buf.PendingImage> _activeImages = const <buf.PendingImage>[];

  int _lastComparedCells = 0;
  int _lastAnsiRuns = 0;
  int _lastWrittenCells = 0;
  int _lastOutputCodeUnits = 0;

  /// Number of cells compared by the most recent differential frame.
  int get lastComparedCells => _lastComparedCells;

  /// Enables DECSTBM/CSI S/T acceleration for full-width vertical viewports.
  bool enableHardwareScrollRegions = true;

  int _lastPartialPaintBoundaries = 0;
  int get lastPartialPaintBoundaries => _lastPartialPaintBoundaries;

  /// Number of cursor-positioned ANSI runs emitted by the most recent frame.
  int get lastAnsiRuns => _lastAnsiRuns;

  /// Number of terminal cells rewritten by the most recent frame.
  int get lastWrittenCells => _lastWrittenCells;

  /// Number of UTF-16 code units emitted, including ANSI style sequences.
  int get lastOutputCodeUnits => _lastOutputCodeUnits;

  // Event-driven loop support
  final _eventLoopController = StreamController<void>.broadcast();
  Stream<void> get _eventLoopStream => _eventLoopController.stream;

  // Debug frame counting
  int _frameCount = 0;
  int _buildCount = 0;
  int _layoutCount = 0;
  int _paintCount = 0;
  DateTime? _statsStartTime;

  /// Get current performance stats and reset counters.
  /// Returns a map with fps, builds/sec, layouts/sec, paints/sec.
  Map<String, double> getPerformanceStats() {
    final now = DateTime.now();
    final start = _statsStartTime ?? now;
    final elapsed = now.difference(start).inMilliseconds / 1000.0;

    if (elapsed < 0.001) {
      return {'fps': 0, 'builds': 0, 'layouts': 0, 'paints': 0};
    }

    final stats = {
      'fps': _frameCount / elapsed,
      'builds': _buildCount / elapsed,
      'layouts': _layoutCount / elapsed,
      'paints': _paintCount / elapsed,
    };

    // Reset counters
    _frameCount = 0;
    _buildCount = 0;
    _layoutCount = 0;
    _paintCount = 0;
    _statsStartTime = now;

    return stats;
  }

  /// Increment build counter (called from BuildOwner)
  void recordBuild() => _buildCount++;

  /// Increment layout counter
  void recordLayout() => _layoutCount++;

  /// Increment paint counter
  void recordPaint() => _paintCount++;

  // Performance logging
  Timer? _perfLogTimer;

  /// Start logging performance stats every [interval] seconds.
  /// Stats are printed to the cinder log (view with `cinder logs`).
  void startPerformanceLogging({
    Duration interval = const Duration(seconds: 5),
  }) {
    _perfLogTimer?.cancel();
    _statsStartTime = DateTime.now();
    _perfLogTimer = Timer.periodic(interval, (_) {
      final stats = getPerformanceStats();
      final msg = 'PERF: fps=${stats['fps']!.toStringAsFixed(1)}, '
          'builds=${stats['builds']!.toStringAsFixed(1)}/s, '
          'layouts=${stats['layouts']!.toStringAsFixed(1)}/s, '
          'paints=${stats['paints']!.toStringAsFixed(1)}/s';
      // Use print which goes to cinder logs
      print(msg);
    });
  }

  /// Stop performance logging.
  void stopPerformanceLogging() {
    _perfLogTimer?.cancel();
    _perfLogTimer = null;
  }

  StreamSubscription? _inputSubscription;
  StreamSubscription? _resizeSubscription;
  StreamSubscription? _shutdownSubscription;
  Size? _lastKnownSize;

  void _initializePipelineOwner() {
    _pipelineOwner = PipelineOwner();
    _pipelineOwner!.onNeedsVisualUpdate = scheduleFrame;
  }

  /// Stream of keyboard input events (raw strings)
  Stream<String> get input => _inputController.stream;

  /// Stream of every normalized input event before widget dispatch.
  Stream<InputEvent> get inputEvents => _normalizedInputController.stream;

  /// Stream of parsed keyboard events
  Stream<KeyboardEvent> get keyboardEvents => _keyboardEventController.stream;

  /// Stream of parsed mouse events
  Stream<MouseEvent> get mouseEvents => _mouseEventController.stream;

  /// Stream of OSC responses captured from the terminal
  Stream<String> get oscEvents => _oscEventsController.stream;

  /// Initialize the terminal and start the event loop
  void initialize() {
    if (capabilities.supportsAlternateScreen) {
      terminal.enterAlternateScreen();
    }
    if (capabilities.isInteractive) {
      terminal.hideCursor();
    }
    terminal.bindOSCStream(_oscEventsController.stream);
    if (capabilities.isInteractive) {
      terminal.clear();
    }

    ImageCleanupManager.instance.setTerminalWriter((data) {
      if (!capabilities.isInteractive) return;
      terminal.write(data);
      terminal.flush();
    });

    if (capabilities.supportsMouse) {
      terminal.write(EscapeCodes.enable.basicMouseTracking);
      terminal.write(EscapeCodes.enable.buttonEventTracking);
      terminal.write(EscapeCodes.enable.motionTracking);
      terminal.write(EscapeCodes.enable.sgrMouseMode);
    }
    if (capabilities.supportsBracketedPaste) {
      terminal.write(EscapeCodes.enable.bracketedPasteMode);
    }
    if (capabilities.supportsFocusEvents) {
      terminal.write(EscapeCodes.enable.focusReporting);
    }
    if (capabilities.supportsKittyKeyboard) {
      terminal.write(EscapeCodes.enable.kittyKeyboard);
    } else if (capabilities.supportsModifyOtherKeys) {
      terminal.write(EscapeCodes.enable.modifyOtherKeys);
    }
    if (capabilities.isInteractive) {
      terminal.flush();
    }

    _lastKnownSize = terminal.size;
    _startInputHandling();
    _startResizeHandling();
    _startSignalHandling();
  }

  void _startInputHandling() {
    final inputStream = terminal.backend.inputStream;
    if (inputStream == null) return;

    if (capabilities.supportsRawMode) {
      try {
        terminal.backend.enableRawMode();
      } catch (_) {
        // A conservative capability profile may still encounter a backend that
        // loses its TTY between detection and initialization.
      }
    }

    _inputSubscription = inputStream.listen((incomingBytes) {
      var bytes = _processOscSequences(incomingBytes);
      if (bytes.isEmpty) return;

      final now = DateTime.now();
      if (_lastInputTime != null &&
          now.difference(_lastInputTime!) > _bufferStaleTimeout) {
        _inputParser.clear();
      }
      _lastInputTime = now;

      _escapeResolutionTimer?.cancel();
      try {
        _inputParser.addBytes(bytes);
      } on FormatException {
        _inputParser.clear();
        return;
      }

      InputEvent? event;
      while ((event = _inputParser.parseNext()) != null) {
        _dispatchInputEvent(event!);
      }

      if (_inputParser.hasPendingEscape) {
        _escapeResolutionTimer = Timer(escapeAmbiguityTimeout, () {
          final escape = _inputParser.flushPendingEscape();
          if (escape != null) _dispatchInputEvent(escape);
        });
      }

      if (buildOwner.hasDirtyElements) scheduleFrame();

      try {
        _inputController.add(utf8.decode(bytes));
      } catch (_) {
        // Escape sequences and chunked UTF-8 are represented by inputEvents.
      }
    });
  }

  /// Injects a normalized event from an alternate input source such as a web
  /// IME bridge, remote session, or test harness.
  void dispatchInputEvent(InputEvent event) => _dispatchInputEvent(event);

  void _dispatchInputEvent(InputEvent event) {
    if (!_normalizedInputController.isClosed) {
      _normalizedInputController.add(event);
    }

    final disposition = inputRouter.route(event);
    if (disposition != InputDisposition.ignored) return;

    if (event is KeyboardInputEvent) {
      final keyEvent = event.event;
      if (!_keyboardEventController.isClosed) {
        _keyboardEventController.add(keyEvent);
      }
      if (_handleDebugKeyEvent(keyEvent)) return;
      _routeKeyboardEvent(keyEvent);
      return;
    }

    if (event is MouseInputEvent) {
      if (!_mouseEventController.isClosed) {
        _mouseEventController.add(event.event);
      }
      _routeMouseEvent(event.event);
      return;
    }

    if (event is CompositionInputEvent) {
      if (event.isCommit) _dispatchCommittedText(event.text);
      return;
    }

    if (event is TextInputEvent) {
      _dispatchCommittedText(event.text);
    }
  }

  void _dispatchCommittedText(String text) {
    if (text.isEmpty) return;
    final firstRune = text.runes.first;
    final keyEvent = KeyboardEvent(
      logicalKey: LogicalKey(firstRune, 'text-input'),
      character: text,
    );
    if (!_keyboardEventController.isClosed) {
      _keyboardEventController.add(keyEvent);
    }
    _routeKeyboardEvent(keyEvent);
  }

  /// Process bytes in shell mode to extract terminal size OSC sequences
  /// Returns filtered bytes with OSC sequences removed
  List<int> _processOscSequences(List<int> bytes) {
    final result = <int>[];
    int i = 0;

    while (i < bytes.length) {
      // Check for OSC sequence: ESC ] ... BEL or ESC ] ... ST (ESC \)
      if (i + 2 < bytes.length && bytes[i] == 0x1b && bytes[i + 1] == 0x5d) {
        // Found ESC ]
        int end = i + 2;
        bool foundTerminator = false;

        // Look for BEL (0x07) or ST (ESC \ = 0x1b 0x5c) terminator
        while (end < bytes.length) {
          if (bytes[end] == 0x07) {
            // Found BEL terminator
            foundTerminator = true;
            break;
          }
          if (end + 1 < bytes.length &&
              bytes[end] == 0x1b &&
              bytes[end + 1] == 0x5c) {
            // Found ST terminator
            foundTerminator = true;
            end++;
            break;
          }
          end++;
        }

        if (foundTerminator && end < bytes.length) {
          // Extract OSC content
          final oscContent = utf8.decode(
            bytes.sublist(i + 2, end),
            allowMalformed: true,
          );

          // Handle OSC sequence based on command number
          _handleOscSequence(oscContent);

          // Skip this OSC sequence
          i = end + 1;
          continue;
        }
      }

      // Regular byte, keep it
      result.add(bytes[i]);
      i++;
    }

    return result;
  }

  /// Handle a parsed OSC sequence
  void _handleOscSequence(String oscContent) {
    // Parse command number (everything before first semicolon)
    final semicolonIndex = oscContent.indexOf(';');
    if (semicolonIndex == -1) {
      // No semicolon, treat entire content as command
      _oscEventsController.add(oscContent);
      return;
    }

    final command = oscContent.substring(0, semicolonIndex);
    final payload = oscContent.substring(semicolonIndex + 1);
    // Check if backend supports OSC 9999 size updates (shell mode)
    final supportsOscSizeUpdates = terminal.backend.resizeStream != null;
    switch (command) {
      // Custom OSC sequences for shell mode
      case "9999" when supportsOscSizeUpdates: // Terminal Size
        _handleTerminalSizeOsc(payload);
        _oscEventsController.add(oscContent);
        break;
      // Standard OSC sequences
      case "0": // Set icon name and window title
      case "1": // Set icon name
      case "2": // Set window title
      case "4": // Set/query color palette
      case "10": // Query foreground color response
      case "11": // Query background color response
      case "12": // Query cursor color response
      case "52": // Clipboard operations
        _oscEventsController.add(oscContent);
        break;
      default: // Unknown or unhandled OSC sequence
        break;
    }
  }

  /// Handle terminal size OSC sequence
  void _handleTerminalSizeOsc(String payload) {
    final parts = payload.split(';');
    if (parts.length == 2) {
      try {
        final cols = int.parse(parts[0]);
        final rows = int.parse(parts[1]);
        final newSize = Size(cols.toDouble(), rows.toDouble());

        // Notify backend of size change (it will emit on resizeStream)
        terminal.backend.notifySizeChanged(newSize);

        // Update terminal size
        terminal.updateSize(newSize);
        _lastKnownSize = newSize;

        // Trigger a redraw with new size
        scheduleFrame();
      } catch (e) {
        // Invalid size, ignore
      }
    }
  }

  void _startResizeHandling() {
    // Listen to backend's resize stream
    final resizeStream = terminal.backend.resizeStream;
    if (resizeStream != null) {
      _resizeSubscription = resizeStream.listen((newSize) {
        if (_lastKnownSize == null ||
            _lastKnownSize!.width != newSize.width ||
            _lastKnownSize!.height != newSize.height) {
          _lastKnownSize = newSize;
          terminal.updateSize(newSize);
          // Drop both buffers to force a correctly sized full redraw.
          _previousBuffer = null;
          _nextBuffer = null;
          scheduleFrame();
        }
      });
    }
  }

  void _startSignalHandling() {
    // Listen to backend's shutdown stream
    final shutdownStream = terminal.backend.shutdownStream;
    if (shutdownStream != null) {
      _shutdownSubscription = shutdownStream.listen((_) {
        // Create a synthetic Ctrl+C keyboard event
        final ctrlCEvent = KeyboardEvent(
          logicalKey: LogicalKey.keyC,
          character: null,
          modifiers: const ModifierKeys(ctrl: true),
        );

        // Add to keyboard event stream for monitoring
        _keyboardEventController.add(ctrlCEvent);

        // Route through widget tree - components can intercept by returning true
        final handled = _routeKeyboardEvent(ctrlCEvent);

        // If no widget handled it, perform default shutdown
        if (!handled) {
          _performImmediateShutdown();
          terminal.backend.requestExit(0);
        }
      });
    }
  }

  void _cancelRuntimeResources() {
    pendingFrameTimer?.cancel();
    _perfLogTimer?.cancel();
    _escapeResolutionTimer?.cancel();
    unawaited(_inputSubscription?.cancel() ?? Future<void>.value());
    unawaited(_resizeSubscription?.cancel() ?? Future<void>.value());
    unawaited(_shutdownSubscription?.cancel() ?? Future<void>.value());
  }

  void _closeRuntimeControllers() {
    for (final controller in <StreamController<dynamic>>[
      _inputController,
      _normalizedInputController,
      _keyboardEventController,
      _mouseEventController,
      _oscEventsController,
    ]) {
      if (!controller.isClosed) unawaited(controller.close());
    }

    if (!_eventLoopController.isClosed) {
      _eventLoopController.add(null);
      unawaited(_eventLoopController.close());
    }
  }

  void _restoreTerminalState() {
    if (capabilities.isInteractive) {
      try {
        if (capabilities.supportsMouse) {
          terminal.backend.writeRaw(EscapeCodes.disable.motionTracking);
          terminal.backend.writeRaw(EscapeCodes.disable.sgrMouseMode);
          terminal.backend.writeRaw(EscapeCodes.disable.buttonEventTracking);
          terminal.backend.writeRaw(EscapeCodes.disable.basicMouseTracking);
        }
        if (capabilities.supportsBracketedPaste) {
          terminal.backend.writeRaw(EscapeCodes.disable.bracketedPasteMode);
        }
        if (capabilities.supportsFocusEvents) {
          terminal.backend.writeRaw(EscapeCodes.disable.focusReporting);
        }
        if (capabilities.supportsKittyKeyboard) {
          terminal.backend.writeRaw(EscapeCodes.disable.kittyKeyboard);
        }
        if (capabilities.supportsModifyOtherKeys) {
          terminal.backend.writeRaw(EscapeCodes.disable.modifyOtherKeys);
        }
        terminal.restoreColors();
        terminal.showCursor();
        if (capabilities.supportsAlternateScreen) {
          terminal.leaveAlternateScreen();
        }
        terminal.flush();
      } catch (_) {
        // Continue to raw-mode restoration even if the output backend failed.
      }
    }

    if (capabilities.supportsRawMode) {
      try {
        terminal.backend.disableRawMode();
      } catch (_) {
        // The TTY may already have disappeared during process shutdown.
      }
    }
  }

  /// Perform immediate synchronous shutdown for signal handlers.
  ///
  /// Every cleanup stage is isolated so a failing user dispose callback cannot
  /// prevent terminal restoration or singleton release.
  void _performImmediateShutdown() {
    if (_shouldExit) return;
    _shouldExit = true;

    _cancelRuntimeResources();

    try {
      detachRootWidget();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }

    _closeRuntimeControllers();

    try {
      shutdownWithHotReload();
    } catch (_) {}

    try {
      ImageCleanupManager.instance.clearAllImages();
    } catch (_) {}

    _restoreTerminalState();
    disposeBinding();
    if (identical(_instance, this)) _instance = null;
  }

  /// Handle global debug key combinations.
  ///
  /// Returns true if the event was handled by the debug system.
  /// Currently handles:
  /// - Ctrl+G: Toggle debug mode
  bool _handleDebugKeyEvent(KeyboardEvent event) {
    // Ctrl+G: Toggle debug mode
    // This sends 0x07 (BEL) which is rarely used by applications
    if (event.logicalKey == LogicalKey.keyG && event.isControlPressed) {
      toggleDebugMode();
      // Schedule a frame to update the UI
      scheduleFrame();
      return true;
    }

    return false;
  }

  /// Route a keyboard event through the widget tree
  /// Returns true if the event was handled by a widget
  bool _routeKeyboardEvent(KeyboardEvent event) {
    if (rootElement == null) return false;

    // Try to dispatch the event to the root element
    // The event will bubble through focused components
    return _dispatchKeyToElement(rootElement!, event);
  }

  /// Route a mouse event through the widget tree
  void _routeMouseEvent(MouseEvent event) {
    if (rootElement == null) {
      return;
    }

    // Handle wheel events for scrollable widgets
    if (event.button == MouseButton.wheelUp ||
        event.button == MouseButton.wheelDown) {
      // Find the render object at the mouse position
      final renderObject = _findRenderObjectInTree(rootElement!);
      if (renderObject != null) {
        _dispatchMouseWheelAtPosition(
          rootElement!,
          event,
          Offset(event.x.toDouble(), event.y.toDouble()),
          Offset.zero,
        );
      }
    }

    // Perform hit test for all mouse events
    final renderObject = _findRenderObjectInTree(rootElement!);
    if (renderObject != null) {
      final hitTestResult = MouseHitTestResult();
      // Mouse coordinates are already 0-based (converted by MouseParser)
      final position = Offset(event.x.toDouble(), event.y.toDouble());

      // Perform hit test from the root render object
      renderObject.hitTest(hitTestResult, position: position);

      // Update mouse tracker with hit test results
      _mouseTracker.updateAnnotations(hitTestResult, event);
    }
  }

  /// Find the render object in the element tree
  RenderObject? _findRenderObjectInTree(Element element) {
    if (element is RenderObjectElement) {
      return element.renderObject;
    }
    RenderObject? result;
    element.visitChildren((child) {
      result ??= _findRenderObjectInTree(child);
    });
    return result;
  }

  /// Dispatch a keyboard event to an element and its children
  bool _dispatchKeyToElement(Element element, KeyboardEvent event) {
    // Check if this element is a BlockFocus that's blocking
    if (element is BlockFocusElement && element.isBlocking) {
      // Block all keyboard events from reaching children
      return true; // Event is handled (blocked)
    }

    // TODO: This is a hack to handle RenderTheater specially for Navigator
    // Should be properly integrated into the render object hierarchy
    if (element.renderObject is RenderTheater) {
      final multiChildRenderObject = element as MultiChildRenderObjectElement;
      if (multiChildRenderObject.children.isNotEmpty) {
        final child = multiChildRenderObject.children.last;
        return _dispatchKeyToElement(child, event);
      }
    }

    // First, try to dispatch to children (depth-first)
    bool handled = false;
    element.visitChildren((child) {
      if (!handled) {
        handled = _dispatchKeyToElement(child, event);
      }
    });

    // If no child handled it, and this element can handle keys, try it
    if (!handled && element is FocusableElement) {
      handled = element.handleKeyEvent(event);
    }

    return handled;
  }

  /// Dispatch a mouse wheel event to scrollable RenderObjects at a specific position
  bool _dispatchMouseWheelAtPosition(
    Element element,
    MouseEvent event,
    Offset mousePos,
    Offset currentOffset,
  ) {
    // TODO: This is a hack to handle RenderTheater specially for Navigator
    // Should be properly integrated into the render object hierarchy
    if (element.renderObject is RenderTheater) {
      final multiChildRenderObject = element as MultiChildRenderObjectElement;
      if (multiChildRenderObject.children.isNotEmpty) {
        final child = multiChildRenderObject.children.last;
        return _dispatchMouseWheelAtPosition(
          child,
          event,
          mousePos,
          currentOffset,
        );
      }
    }

    // Calculate this element's bounds if it has a render object
    Rect? elementBounds;
    RenderObject? renderObject;

    if (element is RenderObjectElement) {
      renderObject = element.renderObject;
      final size = renderObject.size;

      // Get the offset from parent data if available
      Offset localOffset = currentOffset;
      if (renderObject.parentData is BoxParentData) {
        final boxParentData = renderObject.parentData as BoxParentData;
        localOffset = currentOffset + boxParentData.offset;
      }

      elementBounds = Rect.fromLTWH(
        localOffset.dx,
        localOffset.dy,
        size.width,
        size.height,
      );
    }

    // Check if mouse is within this element's bounds
    bool isWithinBounds = elementBounds?.contains(mousePos) ?? true;

    if (!isWithinBounds) {
      return false; // Mouse is outside this element
    }

    // Try to dispatch to children first (depth-first, but only if within their bounds)
    bool handled = false;

    // Calculate offset for children
    Offset childrenOffset = currentOffset;
    if (element is RenderObjectElement && elementBounds != null) {
      // Use the element's actual position for its children
      childrenOffset = Offset(elementBounds.left, elementBounds.top);
    }

    // Visit children in reverse order to respect visual stacking
    // (last child is visually on top in Stack-like containers)
    final children = <Element>[];
    element.visitChildren((child) {
      children.add(child);
    });

    for (final child in children.reversed) {
      if (!handled) {
        handled = _dispatchMouseWheelAtPosition(
          child,
          event,
          mousePos,
          childrenOffset,
        );
      }
    }

    // If no child handled it and this element's render object is scrollable, handle it here
    if (!handled &&
        renderObject != null &&
        renderObject is ScrollableRenderObjectMixin) {
      final scrollableRenderObject =
          renderObject as ScrollableRenderObjectMixin;
      // Check if the render object implements scrolling through duck typing
      // This allows the RenderObject to handle scrolling without importing the mixin
      handled = scrollableRenderObject.handleMouseWheel(event);
    }

    return handled;
  }

  /// Run the main event loop
  Future<void> runEventLoop() async {
    executeFrame();

    final exitCompleter = Completer<void>();
    final subscription = _eventLoopStream.listen((_) {});
    final exitPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_shouldExit && !exitCompleter.isCompleted) {
        exitCompleter.complete();
      }
    });

    try {
      await exitCompleter.future;
    } finally {
      exitPoll.cancel();
      await subscription.cancel();
    }
  }

  /// Shutdown the terminal and cleanup.
  void shutdown() {
    _performImmediateShutdown();
  }

  @override
  void scheduleFrameImpl() {
    // Override scheduler's frame implementation to also wake the event loop.
    // Uses pendingFrameTimer from SchedulerBinding for rate limiting.

    // Don't schedule if a timer is already pending
    if (pendingFrameTimer != null && pendingFrameTimer!.isActive) {
      return;
    }

    if (enableFrameRateLimiting && lastFrameTime != null) {
      final now = DateTime.now();
      final elapsed = now.difference(lastFrameTime!);

      if (elapsed < targetFrameDuration) {
        // Too soon, delay the frame
        final delay = targetFrameDuration - elapsed;
        pendingFrameTimer = Timer(delay, () {
          pendingFrameTimer = null;
          _executeFrameAndWakeEventLoop();
        });
        return;
      }
    }

    // Execute frame immediately (but still async to allow event loop to process)
    pendingFrameTimer = Timer(Duration.zero, () {
      pendingFrameTimer = null;
      _executeFrameAndWakeEventLoop();
    });
  }

  /// Executes frame and wakes the event loop.
  void _executeFrameAndWakeEventLoop() {
    executeFrame();

    // Wake up the event loop after executing the frame
    if (!_eventLoopController.isClosed) {
      _eventLoopController.add(null);
    }
  }

  @override
  void handleDrawFrame() {
    _frameCount++;
    _statsStartTime ??= DateTime.now();

    if (rootElement == null) {
      super.handleDrawFrame(); // Let scheduler handle phase transitions
      return;
    }

    // Execute the persistent callbacks (build phase happens via BuildOwner)
    // The SchedulerBinding's handleDrawFrame will:
    // 1. Call persistent callbacks (including our _drawFrameCallback)
    // 2. Run post-frame callbacks
    // 3. Return to idle phase
    super.handleDrawFrame();
  }

  buf.Buffer _prepareNextBuffer(int width, int height) {
    var buffer = _nextBuffer;
    if (buffer == null || buffer.width != width || buffer.height != height) {
      buffer = buf.Buffer(width, height);
      _nextBuffer = buffer;
    } else {
      buffer.clearAll();
    }
    return buffer;
  }

  buf.Buffer _preparePartialBuffer(int width, int height) {
    final previous = _previousBuffer;
    var buffer = _nextBuffer;
    if (previous == null ||
        previous.width != width ||
        previous.height != height ||
        buffer == null ||
        buffer.width != width ||
        buffer.height != height) {
      return _prepareNextBuffer(width, height);
    }
    buffer.synchronizeFrom(previous);
    return buffer;
  }

  List<RenderObject> _topmostDirtyBoundaries(List<RenderObject> nodes) {
    final boundaries = nodes.where((node) => node.isRepaintBoundary).toSet();
    return boundaries.where((node) {
      RenderObject? ancestor = node.parent;
      while (ancestor != null) {
        if (boundaries.contains(ancestor)) return false;
        ancestor = ancestor.parent;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.depth.compareTo(b.depth));
  }

  void _applyHardwareScrollRequests(buf.Buffer previous, int screenWidth) {
    final requests = pipelineOwner.takeTerminalScrollRequests();
    if (!enableHardwareScrollRegions) return;
    for (final request in requests) {
      final top = request.top.clamp(0, previous.height);
      final bottom = (request.top + request.height).clamp(0, previous.height);
      final lines = request.lines;
      final fullWidth = request.left == 0 && request.width == screenWidth;
      if (!fullWidth ||
          top >= bottom ||
          lines == 0 ||
          lines.abs() >= bottom - top) {
        continue;
      }
      if (previous.hasImageInRegion(top, bottom)) continue;

      terminal.write(EscapeCodes.setScrollRegion(top, bottom));
      terminal.moveCursor(0, top);
      terminal.write(lines > 0
          ? EscapeCodes.scrollUp(lines)
          : EscapeCodes.scrollDown(-lines));
      terminal.write(EscapeCodes.resetScrollRegion);
      previous.scrollRegion(top, bottom, lines);
    }
  }

  /// Renders only the cells that changed since the previous frame.
  void _renderDifferential(buf.Buffer buffer) {
    final previous = _previousBuffer;

    // First frame or size changed: full redraw
    if (previous == null ||
        previous.width != buffer.width ||
        previous.height != buffer.height) {
      _renderFull(buffer);
      return;
    }

    // Full buffer diff - compare every cell
    _renderFullDiff(buffer, previous);
  }

  /// Dirty-span differential renderer with cost-aware row batching.
  void _renderFullDiff(buf.Buffer buffer, buf.Buffer previous) {
    final stats = emitFrameDiff(
      current: buffer,
      previous: previous,
      emitRun: (x, y, output) {
        terminal.moveCursor(x, y);
        terminal.write(output);
      },
    );
    _lastComparedCells = stats.comparedCells;
    _lastAnsiRuns = stats.ansiRuns;
    _lastWrittenCells = stats.writtenCells;
    _lastOutputCodeUnits = stats.outputCodeUnits;

    _renderPendingImages(buffer);
  }

  /// Full redraw (used for first frame or after resize).
  void _renderFull(buf.Buffer buffer) {
    // Clear the screen first to remove any artifacts from previous renders
    // (especially important when terminal size shrinks)
    terminal.write(EscapeCodes.clearScreen);
    terminal.moveTo(0, 0);
    TextStyle? currentStyle;

    for (int y = 0; y < buffer.height; y++) {
      for (int x = 0; x < buffer.width; x++) {
        final cell = buffer.getCell(x, y);

        // Skip zero-width space markers (used for wide character tracking)
        if (cell.char == '\u200B') {
          continue;
        }

        // Skip image placeholder cells - write space to maintain positioning
        if (cell.isImagePlaceholder) {
          if (currentStyle != null) {
            terminal.write(TextStyle.reset);
            currentStyle = null;
          }
          terminal.write(' ');
          continue;
        }

        // Handle style
        final hasStyle = cell.style.color != null ||
            cell.style.backgroundColor != null ||
            cell.style.fontWeight == FontWeight.bold ||
            cell.style.fontWeight == FontWeight.dim ||
            cell.style.fontStyle == FontStyle.italic ||
            cell.style.decoration?.hasUnderline == true ||
            cell.style.reverse;

        if (hasStyle) {
          if (currentStyle != cell.style) {
            if (currentStyle != null) {
              terminal.write(TextStyle.reset);
            }
            terminal.write(cell.style.toAnsi());
            currentStyle = cell.style;
          }
          terminal.write(cell.char);
        } else {
          if (currentStyle != null) {
            terminal.write(TextStyle.reset);
            currentStyle = null;
          }
          terminal.write(cell.char);
        }
      }
      if (y < buffer.height - 1) {
        terminal.write('\n');
      }
    }

    // Reset style at end
    if (currentStyle != null) {
      terminal.write(TextStyle.reset);
    }

    // A full-screen clear removes native image overlays, so re-emit them.
    _renderPendingImages(buffer, force: true);

    // Intentionally do NOT flush here. See _renderFullDiff for the full
    // rationale; the same split-frame issue applies here on the
    // first-frame / post-resize path.
  }

  // Detailed timing instrumentation for profiling
  int _profileBuildTime = 0;
  int _profileLayoutTime = 0;
  int _profilePaintTime = 0;
  int _profileDiffTime = 0;
  int _profileBufferAllocTime = 0;
  int _profileFrames = 0;
  bool _enableDetailedProfiling = false;

  /// Enable detailed profiling that measures time spent in each render phase.
  /// Results are printed every 5 seconds to cinder logs.
  void startDetailedProfiling() {
    _enableDetailedProfiling = true;
    _profileFrames = 0;
    _profileBuildTime = 0;
    _profileLayoutTime = 0;
    _profilePaintTime = 0;
    _profileDiffTime = 0;
    _profileBufferAllocTime = 0;

    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_enableDetailedProfiling) {
        timer.cancel();
        return;
      }
      _reportDetailedProfile();
    });
  }

  /// Stop detailed profiling.
  void stopDetailedProfiling() {
    _enableDetailedProfiling = false;
  }

  void _reportDetailedProfile() {
    if (_profileFrames == 0) return;

    final avgBuild = _profileBuildTime ~/ _profileFrames;
    final avgLayout = _profileLayoutTime ~/ _profileFrames;
    final avgPaint = _profilePaintTime ~/ _profileFrames;
    final avgDiff = _profileDiffTime ~/ _profileFrames;
    final avgAlloc = _profileBufferAllocTime ~/ _profileFrames;
    final total = avgBuild + avgLayout + avgPaint + avgDiff + avgAlloc;

    print('=== DETAILED PROFILE ($_profileFrames frames) ===');
    print('  Buffer alloc: $avgAllocμs (${_pct(avgAlloc, total)}%)');
    print('  Build:        $avgBuildμs (${_pct(avgBuild, total)}%)');
    print('  Layout:       $avgLayoutμs (${_pct(avgLayout, total)}%)');
    print('  Paint:        $avgPaintμs (${_pct(avgPaint, total)}%)');
    print('  Diff render:  $avgDiffμs (${_pct(avgDiff, total)}%)');
    print('  TOTAL:        $totalμs per frame');
    print('');

    // Reset
    _profileFrames = 0;
    _profileBuildTime = 0;
    _profileLayoutTime = 0;
    _profilePaintTime = 0;
    _profileDiffTime = 0;
    _profileBufferAllocTime = 0;
  }

  String _pct(int value, int total) {
    if (total == 0) return '0.0';
    return (value * 100 / total).toStringAsFixed(1);
  }

  /// Reconciles terminal image overlays with the current frame.
  void _renderPendingImages(buf.Buffer buffer, {bool force = false}) {
    final cleanups = ImageCleanupManager.instance.consumePendingCleanups();
    for (final region in cleanups) {
      _clearImageRegion(region.x, region.y, region.width, region.height);
    }

    for (final image in buffer.pendingImages) {
      final alreadyVisible = _activeImages.any(image.samePlacement);
      if (force || !alreadyVisible) {
        terminal.writeInlineImage(image.encodedData, image.x, image.y);
      }
    }
    _activeImages = List<buf.PendingImage>.unmodifiable(buffer.pendingImages);
  }

  /// Clears an image region by writing spaces.
  ///
  /// This is used to clean up Sixel/iTerm2 images when they are unmounted,
  /// since these protocols don't have native delete commands.
  void _clearImageRegion(int x, int y, int width, int height) {
    for (int row = 0; row < height; row++) {
      terminal.moveCursor(x, y + row);
      terminal.write(' ' * width);
    }
  }

  /// Find the focused [RenderTextField] by walking the element tree.
  ///
  /// Looks for a [FocusableElement] whose [Focusable] widget has
  /// `focused == true` and which contains a [RenderTextField] in its
  /// subtree. Returns `null` if no focused text field is found.
  RenderTextField? _findFocusedRenderTextField() {
    if (rootElement == null) return null;

    // Walk the tree looking for a FocusableElement with focused == true
    // that contains a RenderTextField
    FocusableElement? focusedElement;
    void findFocused(Element element) {
      if (focusedElement != null) return;
      if (element is FocusableElement && element.widget.focused) {
        focusedElement = element;
        return;
      }
      element.visitChildren(findFocused);
    }

    findFocused(rootElement!);
    if (focusedElement == null) return null;

    // Now find the RenderTextField inside the focused element's subtree
    RenderTextField? result;
    void findTextField(Element element) {
      if (result != null) return;
      if (element is RenderObjectElement &&
          element.renderObject is RenderTextField) {
        result = element.renderObject as RenderTextField;
        return;
      }
      element.visitChildren(findTextField);
    }

    findTextField(focusedElement!);
    return result;
  }

  /// Position the physical terminal cursor at the IME composition position
  /// of the focused text field (if any).
  ///
  /// When using an Input Method Editor (IME) such as Chinese Pinyin, the
  /// terminal emulator displays the composition/preedit window at the
  /// current cursor position. During differential rendering the cursor
  /// jumps around the screen to write changed cells, causing the IME
  /// window to flicker randomly.
  ///
  /// By repositioning the terminal cursor to the text field's cursor
  /// location *after* every frame render, we give the IME a stable
  /// anchor point. We also show the terminal cursor when a text field
  /// is focused so that terminal emulators that require a visible cursor
  /// for IME positioning work correctly.
  void _positionImeCursor() {
    final renderTextField = _findFocusedRenderTextField();
    if (renderTextField == null) {
      // No focused text field – hide the terminal cursor (normal TUI mode).
      if (_imeCursorVisible) {
        terminal.hideCursor();
        _imeCursorVisible = false;
      }
      return;
    }

    final imePosition = renderTextField.getImeCursorPosition();
    if (imePosition != null) {
      // Move the physical terminal cursor to the text field's cursor position.
      terminal.moveCursor(imePosition.dx.round(), imePosition.dy.round());

      // Show the terminal cursor so that IME composition windows
      // (e.g. Chinese Pinyin) appear at the correct screen position.
      if (!_imeCursorVisible) {
        terminal.showCursor();
        _imeCursorVisible = true;
      }
    }
  }

  /// Tracks whether the terminal cursor is currently visible (shown for IME).
  /// We keep this in sync to avoid sending redundant show/hide sequences.
  bool _imeCursorVisible = false;

  /// The actual frame drawing logic, registered as a persistent callback.
  void _drawFrameCallback(Duration timeStamp) {
    if (rootElement == null) return;

    // Check if we need to do visual work BEFORE the build phase
    // We check this early to avoid unnecessary work
    final needsBuild = buildOwner.hasDirtyElements;
    final needsLayout = pipelineOwner.hasNodesToLayout;
    final needsPaint = pipelineOwner.hasNodesToPaint;

    // Also check root render object flags since markNeedsLayout/Paint
    // sets boolean flags without always adding to dirty lists.
    // This is critical for scrolling - scroll offsets trigger markNeedsLayout
    // which sets the flag but doesn't add to _nodesNeedingLayout.
    bool rootNeedsWork = false;
    if (!needsBuild && !needsLayout && !needsPaint) {
      RenderObject? findRootRenderObject(Element element) {
        if (element is RenderObjectElement) {
          return element.renderObject;
        }
        RenderObject? result;
        element.visitChildren((child) {
          result ??= findRootRenderObject(child);
        });
        return result;
      }

      final rootRender = findRootRenderObject(rootElement!);
      if (rootRender != null) {
        rootNeedsWork = rootRender.needsLayout || rootRender.needsPaint;
      }
    }

    // If nothing needs visual update and we have a previous buffer, skip entirely
    if (!needsBuild &&
        !needsLayout &&
        !needsPaint &&
        !rootNeedsWork &&
        _previousBuffer != null) {
      // Nothing to do - reuse previous frame
      // Still call super.drawFrame() to maintain proper phase transitions
      super.drawFrame();
      return;
    }

    final profiling = _enableDetailedProfiling;
    int t0 = 0, t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0;

    t0 = DateTime.now().microsecondsSinceEpoch;

    // Build phase - handled by BuildOwner via persistent callback
    super.drawFrame();

    t1 = DateTime.now().microsecondsSinceEpoch;
    // Report build end time to scheduler for FrameTiming
    currentFrameBuildEnd = t1;

    // Get current terminal size (may have been updated by resize event)
    final size = terminal.size;
    final width = size.width.toInt();
    final height = size.height.toInt();
    final screenRect = Rect.fromLTWH(
      0,
      0,
      size.width.toDouble(),
      size.height.toDouble(),
    );

    t2 = DateTime.now().microsecondsSinceEpoch;

    // Find render object in tree
    RenderObject? findRenderObject(Element element) {
      if (element is RenderObjectElement) {
        return element.renderObject;
      }
      RenderObject? result;
      element.visitChildren((child) {
        result ??= findRenderObject(child);
      });
      return result;
    }

    final renderObject = findRenderObject(rootElement!);

    if (renderObject != null) {
      // Attach render object to pipeline owner if needed
      if (renderObject.owner != pipelineOwner) {
        renderObject.attach(pipelineOwner);
      }

      final layoutWasDirty =
          renderObject.needsLayout || pipelineOwner.hasNodesToLayout;

      // Layout phase
      renderObject.layout(
        BoxConstraints.tight(
          Size(size.width.toDouble(), size.height.toDouble()),
        ),
      );
      pipelineOwner.flushLayout();

      t3 = DateTime.now().microsecondsSinceEpoch;
      currentFrameLayoutEnd = t3;

      final dirtyPaintNodes = pipelineOwner.takeNodesNeedingPaint();
      final boundaries = _topmostDirtyBoundaries(dirtyPaintNodes);
      final canPartialPaint = _previousBuffer != null &&
          !layoutWasDirty &&
          dirtyPaintNodes.isNotEmpty &&
          boundaries.length == dirtyPaintNodes.toSet().length &&
          boundaries.every((node) =>
              node is RenderRepaintBoundary && node.lastPaintOffset != null);

      final buffer = canPartialPaint
          ? _preparePartialBuffer(width, height)
          : _prepareNextBuffer(width, height);
      final canvas = TerminalCanvas(buffer, screenRect);

      if (canPartialPaint) {
        _lastPartialPaintBoundaries = boundaries.length;
        for (final node in boundaries.cast<RenderRepaintBoundary>()) {
          node.paintWithContext(canvas, node.lastPaintOffset!);
        }
      } else {
        _lastPartialPaintBoundaries = 0;
        renderObject.paintWithContext(canvas, Offset.zero);
        pipelineOwner.clearPaintQueue();
      }

      _pendingFrameBuffer = buffer;
    }

    final buffer = _pendingFrameBuffer ?? _prepareNextBuffer(width, height);
    _pendingFrameBuffer = null;

    t4 = DateTime.now().microsecondsSinceEpoch;
    // Report paint end time to scheduler for FrameTiming
    currentFramePaintEnd = t4;

    // DEC synchronized output makes the terminal present the complete frame
    // atomically. Unsupported terminals safely ignore private mode 2026.
    terminal.write(EscapeCodes.beginSynchronizedOutput);
    try {
      final previous = _previousBuffer;
      if (previous != null) {
        _applyHardwareScrollRequests(previous, width);
      } else {
        pipelineOwner.takeTerminalScrollRequests();
      }
      _renderDifferential(buffer);

      // Keep IME composition anchored after all cursor-moving diff runs.
      _positionImeCursor();
    } finally {
      terminal.write(EscapeCodes.endSynchronizedOutput);
      terminal.flush();
    }

    if (profiling) {
      t5 = DateTime.now().microsecondsSinceEpoch;
      _profileFrames++;
      _profileBuildTime += (t1 - t0);
      _profileBufferAllocTime += (t2 - t1);
      _profileLayoutTime += (t3 - t2);
      _profilePaintTime += (t4 - t3);
      _profileDiffTime += (t5 - t4);
    }

    // Swap reusable front/back buffers. The old front becomes the next
    // paint target and will clear only the spans it touched previously.
    final reusable = _previousBuffer;
    _previousBuffer = buffer;
    _nextBuffer = reusable;

    // Rotate rainbow debug color for next frame
    if (debugRepaintRainbowEnabled) {
      debugCurrentRepaintColor = debugCurrentRepaintColor.withHue(
        (debugCurrentRepaintColor.hue + 2.0) % 360.0,
      );
    }
  }

  @override
  void initializeBinding() {
    super.initializeBinding();
    // Register the terminal drawing as a persistent callback
    addPersistentFrameCallback(_drawFrameCallback);
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    registerBoolServiceExtension(
      name: 'repaintRainbow',
      getter: () async => debugRepaintRainbowEnabled,
      setter: (bool value) async {
        debugRepaintRainbowEnabled = value;
        // Force a repaint when toggling
        scheduleFrame();
      },
    );
  }

  /// Request application shutdown with proper cleanup
  ///
  /// This is the recommended way to exit a cinder application.
  /// It ensures all terminal cleanup (including mouse tracking disable)
  /// happens before the process exits.
  ///
  /// IMPORTANT: Do NOT call dart:io's exit() directly, as it will bypass
  /// terminal cleanup and may leave the terminal in a broken state (e.g.,
  /// mouse movement producing escape sequences).
  ///
  /// Instead, always use this method or set [_shouldExit] to true.
  void requestShutdown([int exitCode = 0]) {
    _performImmediateShutdown();
    terminal.backend.requestExit(exitCode);
  }
}
