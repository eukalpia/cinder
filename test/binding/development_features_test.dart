import 'package:cinder/cinder.dart';
import 'package:cinder/src/binding/development_features.dart';
import 'package:test/test.dart';

void main() {
  test('dart test runs with assertions enabled', () {
    expect(assertionsEnabled, isTrue);
  });

  group('resolveDevelopmentFeature', () {
    test('defaults to the debug-build value without other input', () {
      expect(resolveDevelopmentFeature(debugDefault: false), isFalse);
      expect(resolveDevelopmentFeature(debugDefault: true), isTrue);
    });

    test('recognized environment values override the default', () {
      for (final value in ['1', 'true', 'YES', ' on ']) {
        expect(
          resolveDevelopmentFeature(
            environmentValue: value,
            debugDefault: false,
          ),
          isTrue,
          reason: value,
        );
      }
      for (final value in ['0', 'false', 'No', 'off', '']) {
        expect(
          resolveDevelopmentFeature(
            environmentValue: value,
            debugDefault: true,
          ),
          isFalse,
          reason: value,
        );
      }
    });

    test('unrecognized environment values keep the default', () {
      expect(
        resolveDevelopmentFeature(
          environmentValue: 'maybe',
          debugDefault: true,
        ),
        isTrue,
      );
      expect(
        resolveDevelopmentFeature(
          environmentValue: 'maybe',
          debugDefault: false,
        ),
        isFalse,
      );
    });

    test('an explicit application choice wins', () {
      expect(
        resolveDevelopmentFeature(
          explicit: false,
          environmentValue: '1',
          debugDefault: true,
        ),
        isFalse,
      );
      expect(
        resolveDevelopmentFeature(
          explicit: true,
          environmentValue: '0',
          debugDefault: false,
        ),
        isTrue,
      );
    });
  });

  test('the debug overlay shortcut is Ctrl+G', () {
    KeyboardEvent key(LogicalKey key, {bool ctrl = false}) => KeyboardEvent(
      logicalKey: key,
      modifiers: ModifierKeys(ctrl: ctrl),
    );

    expect(isDebugOverlayShortcut(key(LogicalKey.keyG, ctrl: true)), isTrue);
    expect(isDebugOverlayShortcut(key(LogicalKey.keyG)), isFalse);
    expect(isDebugOverlayShortcut(key(LogicalKey.keyC, ctrl: true)), isFalse);
  });
}
