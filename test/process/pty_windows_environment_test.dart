import 'package:cinder/src/process/native_pty_windows.dart';
import 'package:test/test.dart';

void main() {
  test('Windows environment overrides deduplicate case-insensitive names', () {
    expect(
      normalizeWindowsEnvironment({
        'PATH': 'inherited',
        'SYSTEMROOT': 'inherited-root',
        'Path': 'override',
        'SystemRoot': 'override-root',
      }),
      {'PATH': 'override', 'SYSTEMROOT': 'override-root'},
    );
  });
}
