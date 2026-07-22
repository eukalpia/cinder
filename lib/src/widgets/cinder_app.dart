import 'package:cinder/cinder.dart';

/// The root configuration for a Cinder application.
///
/// [CinderApp] owns terminal metadata, application routing, theming, and
/// declarative runtime diagnostics. Provide either [child] for a simple
/// application or navigation configuration through [home], [routes], and the
/// route factories.
class CinderApp extends StatefulWidget {
  const CinderApp({
    this.title,
    this.iconName,
    this.child,
    this.home,
    this.routes,
    this.initialRoute,
    this.onGenerateRoute,
    this.onUnknownRoute,
    this.navigatorObservers = const [],
    this.navigatorKey,
    this.theme,
    this.debug = CinderDebugOptions.disabled,
    super.key,
  })  : assert(
          child != null ||
              home != null ||
              routes != null ||
              onGenerateRoute != null,
          'Either child, home, routes, or onGenerateRoute must be provided',
        ),
        assert(
          child == null ||
              (home == null &&
                  routes == null &&
                  initialRoute == null &&
                  onGenerateRoute == null &&
                  onUnknownRoute == null),
          'If child is provided, navigation parameters cannot be used',
        );

  /// A one-line description shown in the terminal window title.
  final String? title;

  /// A short application name used by terminal window managers.
  final String? iconName;

  /// The application content when navigation is not required.
  final Widget? child;

  /// The widget for the default route.
  final Widget? home;

  /// The application's named route table.
  final Map<String, Widget Function(BuildContext)>? routes;

  /// The first named route shown by the generated [Navigator].
  final String? initialRoute;

  /// Generates a route that is not present in [routes].
  final RouteFactory? onGenerateRoute;

  /// Generates a fallback route when normal generation fails.
  final RouteFactory? onUnknownRoute;

  /// Observers attached to the generated [Navigator].
  final List<NavigatorObserver> navigatorObservers;

  /// Key used by the generated [Navigator].
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The application theme. When omitted, terminal brightness is detected.
  final TuiThemeData? theme;

  /// Runtime rendering and performance diagnostics.
  final CinderDebugOptions debug;

  @override
  State<CinderApp> createState() => _CinderAppState();
}

class _CinderAppState extends State<CinderApp> {
  TuiThemeData? _detectedTheme;
  bool _detectingTheme = false;

  @override
  void initState() {
    super.initState();
    _updateTitle();
    _detectThemeIfNeeded();
    _applyDebugOptions();
  }

  @override
  void didUpdateWidget(CinderApp oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title ||
        oldWidget.iconName != widget.iconName) {
      _updateTitle();
    }
    if (oldWidget.theme != null && widget.theme == null) {
      _detectThemeIfNeeded();
    }
    if (oldWidget.debug != widget.debug) {
      _applyDebugOptions();
    }
  }

  @override
  void dispose() {
    CinderTimeline.debugTimelineEnabled = false;
    CinderTimeline.metricsEnabled = false;
    debugDetectLayoutThrashing = false;
    debugRepaintRainbowEnabled = false;
    super.dispose();
  }

  void _applyDebugOptions() {
    final options = widget.debug;

    CinderTimeline.debugTimelineEnabled = options.emitTimelineEvents;
    CinderTimeline.metricsEnabled = options.showFrameTimings;
    debugDetectLayoutThrashing = options.detectLayoutThrashing;
    debugRepaintRainbowEnabled = options.showRepaintRegions;

    void updateOverlay() {
      if (!mounted) return;
      if (debugMode != options.showPerformanceOverlay) {
        toggleDebugMode();
      }
      // DebugOverlay historically enables repaint visualization when toggled.
      // Restore the independently configured value afterwards.
      debugRepaintRainbowEnabled = options.showRepaintRegions;
    }

    try {
      SchedulerBinding.instance.addPostFrameCallback((_) => updateOverlay());
    } catch (_) {
      // A binding may not exist while constructing isolated documentation or
      // static analysis examples. Other diagnostic flags still apply.
    }
  }

  void _detectThemeIfNeeded() {
    if (widget.theme != null || _detectingTheme) return;
    _detectingTheme = true;

    final terminal = _currentTerminal();
    if (terminal == null) {
      _detectingTheme = false;
      setState(() => _detectedTheme = TuiThemeData.dark);
      return;
    }

    detectTerminalBrightness(terminal).then((brightness) {
      if (!mounted) return;
      setState(() {
        _detectedTheme = brightness == Brightness.light
            ? TuiThemeData.light
            : TuiThemeData.dark;
        _detectingTheme = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _detectedTheme = TuiThemeData.dark;
        _detectingTheme = false;
      });
    });
  }

  void _updateTitle() {
    final terminal = _currentTerminal();
    if (terminal == null) return;

    final title = _safeMetadata(widget.title);
    final iconName = _safeMetadata(widget.iconName);

    if (title != null && iconName != null) {
      terminal
        ..setWindowTitle(title)
        ..setIconName(iconName)
        ..flush();
    } else if (title != null) {
      terminal
        ..setTitleAndIcon(title)
        ..flush();
    }
  }

  Terminal? _currentTerminal() {
    try {
      final binding = CinderBinding.instance;
      if (binding is TerminalBinding) return binding.terminal;
      if (binding is CinderTestBinding) return binding.terminal;
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _safeMetadata(String? value) {
    if (value == null) return null;
    return TerminalText.safe(
      value,
      preserveNewlines: false,
      preserveTabs: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.child != null) {
      content = widget.child!;
    } else {
      content = Navigator(
        key: widget.navigatorKey,
        home: widget.home,
        routes: widget.routes,
        initialRoute: widget.initialRoute,
        onGenerateRoute: widget.onGenerateRoute,
        onUnknownRoute: widget.onUnknownRoute,
        observers: widget.navigatorObservers,
      );
    }

    final effectiveTheme = widget.theme ?? _detectedTheme;
    if (effectiveTheme == null) return content;

    content = SizedBox.expand(
      child: ColoredBox(
        color: effectiveTheme.background,
        foregroundColor: effectiveTheme.onBackground,
        obscure: true,
        child: content,
      ),
    );

    return TuiTheme(
      data: effectiveTheme,
      child: content,
    );
  }
}
