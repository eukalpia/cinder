import 'package:cinder/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  final cases = [
    (
      text: 'abc',
      width: 3,
      limit: 1,
      lines: ['abc'],
      horizontal: false,
      vertical: false,
    ),
    (
      text: 'abc\n',
      width: 3,
      limit: 1,
      lines: ['abc'],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'a\n\nb',
      width: 3,
      limit: 2,
      lines: ['a', ''],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'a\n',
      width: 3,
      limit: 2,
      lines: ['a', ''],
      horizontal: false,
      vertical: false,
    ),
    (
      text: '',
      width: 3,
      limit: 0,
      lines: <String>[],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'ab cd ef',
      width: 3,
      limit: 2,
      lines: ['ab ', 'cd '],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'abcdefghij',
      width: 3,
      limit: 2,
      lines: ['abc', 'def'],
      horizontal: false,
      vertical: true,
    ),
    (
      text: '你好世界',
      width: 4,
      limit: 1,
      lines: ['你好'],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'e\u0301e\u0301e\u0301',
      width: 2,
      limit: 1,
      lines: ['e\u0301e\u0301'],
      horizontal: false,
      vertical: true,
    ),
    (
      text: '👨‍👩‍👧‍👦X👨‍👩‍👧‍👦',
      width: 3,
      limit: 1,
      lines: ['👨‍👩‍👧‍👦X'],
      horizontal: false,
      vertical: true,
    ),
    (
      text: 'X\n界',
      width: 1,
      limit: 1,
      lines: ['X'],
      horizontal: true,
      vertical: true,
    ),
    (
      text: '\n界',
      width: 1,
      limit: 1,
      lines: [''],
      horizontal: true,
      vertical: true,
    ),
    (
      text: 'abc',
      width: 0,
      limit: 1,
      lines: ['a'],
      horizontal: true,
      vertical: true,
    ),
  ];

  for (final fixture in cases) {
    test(
      'wrapped prefix ${fixture.text} at ${fixture.width}x${fixture.limit}',
      () {
        final result = TextLayoutEngine.layout(
          fixture.text,
          TextLayoutConfig(maxWidth: fixture.width, maxLines: fixture.limit),
        );

        expect(result.lines, fixture.lines);
        expect(result.actualHeight, fixture.lines.length);
        expect(result.didOverflowWidth, fixture.horizontal);
        expect(result.didOverflowHeight, fixture.vertical);
      },
    );
  }

  test('a bounded log preview retains only the requested lines', () {
    final result = TextLayoutEngine.layout(
      'one\ntwo\nthree\n${List.filled(2000, 'hidden log message').join('\n')}',
      const TextLayoutConfig(maxWidth: 80, maxLines: 3),
    );

    expect(result.lines, ['one', 'two', 'three']);
    expect(result.actualWidth, 5);
    expect(result.actualHeight, 3);
    expect(result.didOverflowWidth, isFalse);
    expect(result.didOverflowHeight, isTrue);
  });

  test('height ellipsis preserves a complete wide grapheme', () {
    final result = TextLayoutEngine.layout(
      '👨‍👩‍👧‍👦XXmore text',
      const TextLayoutConfig(
        maxWidth: 5,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    expect(result.lines, ['👨‍👩‍👧‍👦...']);
    expect(result.actualWidth, 5);
    expect(result.didOverflowWidth, isFalse);
    expect(result.didOverflowHeight, isTrue);
  });

  test('unwrapped hidden lines still contribute to width overflow', () {
    final result = TextLayoutEngine.layout(
      'ok\nhidden wide line',
      const TextLayoutConfig(maxWidth: 3, maxLines: 1, softWrap: false),
    );

    expect(result.lines, ['ok']);
    expect(result.actualWidth, 2);
    expect(result.didOverflowWidth, isTrue);
    expect(result.didOverflowHeight, isTrue);
  });
}
