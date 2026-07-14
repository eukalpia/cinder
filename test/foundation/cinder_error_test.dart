import 'package:cinder/cinder.dart';
import 'package:cinder/src/components/error_widget.dart';
import 'package:test/test.dart' hide isNotEmpty;

void main() {
  group('CinderErrorDetails', () {
    test('constructor with all parameters', () {
      final details = CinderErrorDetails(
        exception: Exception('Test error'),
        stack: StackTrace.current,
        library: 'test library',
        context: 'while testing',
        informationCollector: () => ['info1', 'info2'],
        silent: true,
      );

      expect(details.exception, isA<Exception>());
      expect(details.stack, isNotNull);
      expect(details.library, equals('test library'));
      expect(details.context, equals('while testing'));
      expect(details.informationCollector, isNotNull);
      expect(details.silent, isTrue);
    });

    test('constructor with minimal fields (just exception)', () {
      final details = CinderErrorDetails(
        exception: 'Simple string error',
      );

      expect(details.exception, equals('Simple string error'));
      expect(details.stack, isNull);
      expect(details.library, equals('cinder framework')); // default value
      expect(details.context, isNull);
      expect(details.informationCollector, isNull);
      expect(details.silent, isFalse); // default value
    });

    test('toString() with library and context', () {
      final details = CinderErrorDetails(
        exception: 'Test exception',
        library: 'my library',
        context: 'during test execution',
      );

      final output = details.toString();

      expect(output, contains('Exception caught by my library'));
      expect(output, contains('during test execution'));
      expect(output, contains('Test exception'));
    });

    test('toString() with stack trace', () {
      final stack = StackTrace.current;
      final details = CinderErrorDetails(
        exception: 'Error with stack',
        stack: stack,
      );

      final output = details.toString();

      expect(output, contains('Stack trace:'));
      expect(output, contains(stack.toString()));
    });

    test('toString() with informationCollector', () {
      final details = CinderErrorDetails(
        exception: 'Error with extra info',
        informationCollector: () => [
          'Additional detail 1',
          'Additional detail 2',
          'Additional detail 3',
        ],
      );

      final output = details.toString();

      expect(output, contains('Additional information:'));
      expect(output, contains('Additional detail 1'));
      expect(output, contains('Additional detail 2'));
      expect(output, contains('Additional detail 3'));
    });

    test('toString() formatting with all fields', () {
      final stack = StackTrace.fromString('#0 main (test.dart:1:1)');
      final details = CinderErrorDetails(
        exception: 'Complete error',
        stack: stack,
        library: 'complete library',
        context: 'while completing',
        informationCollector: () => ['Complete info'],
      );

      final output = details.toString();

      // Check order and structure
      expect(output, contains('══╡ Exception caught by complete library ╞══'));
      expect(output,
          contains('The following exception was thrown while completing:'));
      expect(output, contains('Complete error'));
      expect(output, contains('Stack trace:'));
      expect(output, contains('#0 main (test.dart:1:1)'));
      expect(output, contains('Additional information:'));
      expect(output, contains('Complete info'));
    });

    test('toString() without library shows no header', () {
      final details = CinderErrorDetails(
        exception: 'No library error',
        library: null,
      );

      final output = details.toString();

      expect(output, isNot(contains('Exception caught by')));
      expect(output, contains('No library error'));
    });
  });

  group('CinderError.onError', () {
    late CinderExceptionHandler? originalHandler;

    setUp(() {
      originalHandler = CinderError.onError;
      CinderError.resetErrorCount();
    });

    tearDown(() {
      CinderError.onError = originalHandler;
      CinderError.resetErrorCount();
    });

    test('default handler is dumpErrorToConsole', () {
      // Reset to default
      CinderError.onError = CinderError.dumpErrorToConsole;

      expect(CinderError.onError, equals(CinderError.dumpErrorToConsole));
    });

    test('custom onError handler is called', () {
      final capturedDetails = <CinderErrorDetails>[];

      CinderError.onError = (details) {
        capturedDetails.add(details);
      };

      final testDetails = CinderErrorDetails(
        exception: 'Test error for custom handler',
      );

      CinderError.reportError(testDetails);

      expect(capturedDetails, hasLength(1));
      expect(capturedDetails.first.exception,
          equals('Test error for custom handler'));
    });

    test('setting onError to null does not crash on reportError', () {
      CinderError.onError = null;

      final testDetails = CinderErrorDetails(
        exception: 'Should not crash',
      );

      // Should not throw
      expect(() => CinderError.reportError(testDetails), returnsNormally);
    });

    test('onError handler can be changed multiple times', () {
      var callCount1 = 0;
      var callCount2 = 0;

      CinderError.onError = (_) => callCount1++;
      CinderError.reportError(CinderErrorDetails(exception: 'Error 1'));

      CinderError.onError = (_) => callCount2++;
      CinderError.reportError(CinderErrorDetails(exception: 'Error 2'));

      expect(callCount1, equals(1));
      expect(callCount2, equals(1));
    });
  });

  group('CinderError.resetErrorCount', () {
    late CinderExceptionHandler? originalHandler;
    setUp(() {
      originalHandler = CinderError.onError;
      CinderError.resetErrorCount();
    });

    tearDown(() {
      CinderError.onError = originalHandler;
      CinderError.resetErrorCount();
    });

    test('resetErrorCount resets the counter', () {
      // Capture print output
      CinderError.onError = CinderError.dumpErrorToConsole;

      // First error should print full details
      CinderError.dumpErrorToConsole(
        CinderErrorDetails(exception: 'First error'),
      );

      // Reset the counter
      CinderError.resetErrorCount();

      // This should again be treated as first error (full details)
      // We can't easily test print output, but we verify no crash
      expect(
        () => CinderError.dumpErrorToConsole(
          CinderErrorDetails(exception: 'After reset'),
        ),
        returnsNormally,
      );
    });
  });

  group('CinderError.reportError', () {
    late CinderExceptionHandler? originalHandler;

    setUp(() {
      originalHandler = CinderError.onError;
      CinderError.resetErrorCount();
    });

    tearDown(() {
      CinderError.onError = originalHandler;
      CinderError.resetErrorCount();
    });

    test('reportError calls onError callback', () {
      var wasCalled = false;

      CinderError.onError = (_) {
        wasCalled = true;
      };

      CinderError.reportError(
        CinderErrorDetails(exception: 'Test'),
      );

      expect(wasCalled, isTrue);
    });

    test('reportError passes correct details to handler', () {
      CinderErrorDetails? receivedDetails;

      CinderError.onError = (details) {
        receivedDetails = details;
      };

      final testDetails = CinderErrorDetails(
        exception: 'Specific error',
        library: 'specific library',
        context: 'specific context',
        silent: true,
      );

      CinderError.reportError(testDetails);

      expect(receivedDetails, isNotNull);
      expect(receivedDetails!.exception, equals('Specific error'));
      expect(receivedDetails!.library, equals('specific library'));
      expect(receivedDetails!.context, equals('specific context'));
      expect(receivedDetails!.silent, isTrue);
    });

    test('reportError does nothing when onError is null', () {
      CinderError.onError = null;

      // Should complete without error
      expect(
        () => CinderError.reportError(
          CinderErrorDetails(exception: 'Should be ignored'),
        ),
        returnsNormally,
      );
    });
  });

  group('CinderError.dumpErrorToConsole', () {
    setUp(() {
      CinderError.resetErrorCount();
    });

    tearDown(() {
      CinderError.resetErrorCount();
    });

    test('first error prints full details', () {
      // We can verify this doesn't crash; actual print testing
      // would require capturing stdout
      expect(
        () => CinderError.dumpErrorToConsole(
          CinderErrorDetails(
            exception: 'First error details',
            library: 'test lib',
            context: 'test context',
          ),
        ),
        returnsNormally,
      );
    });

    test('subsequent errors print shorter summary', () {
      // First error
      CinderError.dumpErrorToConsole(
        CinderErrorDetails(exception: 'Error 1'),
      );

      // Second error - should print shorter format
      expect(
        () => CinderError.dumpErrorToConsole(
          CinderErrorDetails(exception: 'Error 2'),
        ),
        returnsNormally,
      );

      // Third error
      expect(
        () => CinderError.dumpErrorToConsole(
          CinderErrorDetails(exception: 'Error 3'),
        ),
        returnsNormally,
      );
    });
  });

  group('Integration with ErrorThrowingWidget', () {
    late CinderExceptionHandler? originalHandler;
    late List<CinderErrorDetails> capturedErrors;

    setUp(() {
      originalHandler = CinderError.onError;
      capturedErrors = [];
      CinderError.resetErrorCount();

      CinderError.onError = (details) {
        capturedErrors.add(details);
      };
    });

    tearDown(() {
      CinderError.onError = originalHandler;
      CinderError.resetErrorCount();
    });

    test('layout error triggers CinderError.onError', () async {
      await testCinder(
        'layout error integration',
        (tester) async {
          await tester.pumpComponent(
            const ErrorThrowingWidget(
              throwInLayout: true,
              throwInPaint: false,
              errorMessage: 'Layout integration test',
            ),
          );

          // Error should have been captured (layout errors throw IntegerDivisionByZeroException)
          expect(capturedErrors, isNotEmpty);
          // Layout error context contains "performLayout"
          expect(
            capturedErrors.any(
              (d) => d.context?.contains('performLayout') ?? false,
            ),
            isTrue,
          );
        },
      );
    });

    test('paint error triggers CinderError.onError', () async {
      await testCinder(
        'paint error integration',
        (tester) async {
          await tester.pumpComponent(
            const ErrorThrowingWidget(
              throwInLayout: false,
              throwInPaint: true,
              errorMessage: 'Paint integration test',
            ),
          );

          // Error should have been captured
          expect(capturedErrors, isNotEmpty);
          // Paint error uses the errorMessage in the exception
          expect(
            capturedErrors.any(
              (d) => d.exception.toString().contains('Paint integration test'),
            ),
            isTrue,
          );
        },
      );
    });

    test('errors contain contextual information', () async {
      await testCinder(
        'error context',
        (tester) async {
          await tester.pumpComponent(
            const ErrorThrowingWidget(
              throwInLayout: true,
              errorMessage: 'Contextual error',
            ),
          );

          // Should have captured at least one error
          expect(capturedErrors, isNotEmpty);

          // Find any error from rendering (layout errors are IntegerDivisionByZeroException)
          final relevantError = capturedErrors.first;

          // Should have library information
          expect(relevantError.library, isNotNull);

          // Should have context about what was happening
          expect(relevantError.context, isNotNull);
        },
      );
    });

    test('multiple paint errors are captured separately', () async {
      await testCinder(
        'multiple errors',
        (tester) async {
          // Use paint errors since they include the errorMessage in the exception
          await tester.pumpComponent(
            Column(
              children: [
                const ErrorThrowingWidget(
                  throwInLayout: false,
                  throwInPaint: true,
                  errorMessage: 'First paint error',
                ),
                const ErrorThrowingWidget(
                  throwInLayout: false,
                  throwInPaint: true,
                  errorMessage: 'Second paint error',
                ),
              ],
            ),
          );

          // Both errors should be captured
          expect(
            capturedErrors.any(
              (d) => d.exception.toString().contains('First paint error'),
            ),
            isTrue,
          );
          expect(
            capturedErrors.any(
              (d) => d.exception.toString().contains('Second paint error'),
            ),
            isTrue,
          );
        },
      );
    });
  });

  group('Exception type handling', () {
    test('handles Exception objects', () {
      final details = CinderErrorDetails(
        exception: Exception('Standard exception'),
      );

      expect(details.exception, isA<Exception>());
      expect(details.toString(), contains('Standard exception'));
    });

    test('handles Error objects', () {
      final details = CinderErrorDetails(
        exception: StateError('State error'),
      );

      expect(details.exception, isA<StateError>());
      expect(details.toString(), contains('State error'));
    });

    test('handles String errors', () {
      final details = CinderErrorDetails(
        exception: 'Plain string error',
      );

      expect(details.exception, isA<String>());
      expect(details.toString(), contains('Plain string error'));
    });

    test('handles arbitrary objects', () {
      final details = CinderErrorDetails(
        exception: {'error': 'map error'},
      );

      expect(details.exception, isA<Map>());
      expect(details.toString(), contains('error'));
    });
  });
}
