/// Signature for [CinderError.onError] handler.
typedef CinderExceptionHandler = void Function(CinderErrorDetails details);

/// Class for information provided to [CinderExceptionHandler] callbacks.
///
/// Contains detailed information about the exception including the exception
/// itself, stack trace, and contextual information about where the error occurred.
class CinderErrorDetails {
  const CinderErrorDetails({
    required this.exception,
    this.stack,
    this.library = 'cinder framework',
    this.context,
    this.informationCollector,
    this.silent = false,
  });

  /// The exception that was caught.
  final Object exception;

  /// The stack trace from where the exception was thrown.
  final StackTrace? stack;

  /// A human-readable name for the library that caught the error.
  final String? library;

  /// A description of where/what was happening when the error occurred.
  final String? context;

  /// A callback that returns additional diagnostic information.
  final Iterable<String> Function()? informationCollector;

  /// Whether this error should be silent in release mode.
  final bool silent;

  @override
  String toString() {
    final buffer = StringBuffer();
    if (library != null) {
      buffer.writeln('══╡ Exception caught by $library ╞══');
    }
    if (context != null) {
      buffer.writeln('The following exception was thrown $context:');
    }
    buffer.writeln(exception);
    if (stack != null) {
      buffer.writeln('\nStack trace:');
      buffer.writeln(stack);
    }
    if (informationCollector != null) {
      buffer.writeln('\nAdditional information:');
      for (final info in informationCollector!()) {
        buffer.writeln(info);
      }
    }
    return buffer.toString();
  }
}

/// Error reporting mechanism for cinder.
///
/// This class provides a global error handler similar to Flutter's
/// [FlutterError.onError] pattern, allowing users to integrate with
/// crash reporting services like Sentry.
///
/// ## Usage
///
/// Set up a custom error handler at app startup:
///
/// ```dart
/// void main() {
///   CinderError.onError = (details) {
///     // Report to Sentry
///     Sentry.captureException(details.exception, stackTrace: details.stack);
///     // Also log to console
///     CinderError.dumpErrorToConsole(details);
///   };
///   runApp(MyApp());
/// }
/// ```
///
/// ## Default Behavior
///
/// By default, errors are printed to the console via [dumpErrorToConsole].
/// Set [onError] to `null` to silently ignore errors (not recommended).
abstract final class CinderError {
  /// Called whenever cinder catches an error.
  ///
  /// Set to a custom function for crash reporting (Sentry, etc).
  /// Set to null to silently ignore errors (not recommended).
  ///
  /// Example:
  /// ```dart
  /// void main() {
  ///   CinderError.onError = (details) {
  ///     Sentry.captureException(details.exception, stackTrace: details.stack);
  ///     CinderError.dumpErrorToConsole(details); // Still log to console
  ///   };
  ///   runApp(MyApp());
  /// }
  /// ```
  static CinderExceptionHandler? onError = dumpErrorToConsole;

  static int _errorCount = 0;

  /// Resets the error count for [dumpErrorToConsole].
  ///
  /// This is useful in testing to reset the state between tests.
  static void resetErrorCount() {
    _errorCount = 0;
  }

  /// Default error handler - prints to console.
  ///
  /// The first error prints the full details including stack trace.
  /// Subsequent errors print a shorter summary to avoid log spam.
  static void dumpErrorToConsole(CinderErrorDetails details) {
    if (_errorCount == 0) {
      print(details.toString());
    } else {
      print('Another exception: ${details.exception}');
    }
    _errorCount++;
  }

  /// Report an error through the [onError] callback.
  ///
  /// This is the main entry point for reporting errors from within
  /// the cinder framework. Framework code should call this method
  /// instead of printing errors directly.
  static void reportError(CinderErrorDetails details) {
    onError?.call(details);
  }
}
