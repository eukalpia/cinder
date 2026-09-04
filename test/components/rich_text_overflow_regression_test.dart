import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('RichText keeps styles aligned across a split grapheme', () async {
    final result = await renderPlainWidget(
      const RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'e',
              style: TextStyle(color: Colors.red),
            ),
            TextSpan(
              text: '\u0301',
              style: TextStyle(color: Colors.blue),
            ),
            TextSpan(
              text: 'X',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
      size: const Size(4, 1),
    );

    expect(result.lines.single, 'e\u0301X');
    expect(result.buffer.getCell(0, 0).style.color, Colors.red);
    expect(result.buffer.getCell(1, 0).style.color, Colors.green);
  });

  test(
    'RichText truncates each explicit line without losing later styles',
    () async {
      final result = await renderPlainWidget(
        const RichText(
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'abcdefghij\n',
                style: TextStyle(color: Colors.red),
              ),
              TextSpan(
                text: '\nXY',
                style: TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        size: const Size(6, 4),
      );
      expect(result.lines.take(3), ['abc...', '', 'XY']);
      expect(result.buffer.getCell(0, 2).style.color, Colors.blue);
    },
  );

  test(
    'RichText maxLines paints the ellipsis in the retained span style',
    () async {
      final result = await renderPlainWidget(
        const RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'abcdef',
                style: TextStyle(color: Colors.red),
              ),
              TextSpan(
                text: 'ghijkl',
                style: TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        size: const Size(6, 2),
      );
      expect(result.lines.first, 'abc...');
      expect(result.buffer.getCell(3, 0).style.color, Colors.red);
    },
  );
}
