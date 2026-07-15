import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('Flutter-style color API', () {
    test('exposes direct non-conflicting Color aliases', () {
      expect(Color.black, same(Colors.black));
      expect(Color.white, same(Colors.white));
      expect(Color.transparent, same(Colors.transparent));
      expect(Color.deepPurple, same(Colors.deepPurple));
      expect(Color.blueGrey, same(Colors.blueGrey));
    });

    test('keeps chromatic channel names on Colors', () {
      expect(Colors.red.red, 231);
      expect(Colors.green.green, 213);
      expect(Colors.blue.blue, 244);
    });

    test('supports both RRGGBB and Flutter AARRGGBB integers', () {
      expect(const Color(0xFF0000), const Color.fromRGB(255, 0, 0));
      expect(const Color(0x80FF0000), const Color.fromARGB(128, 255, 0, 0));
      expect(const Color(0x80FF0000).toARGB32(), 0x80FF0000);
    });

    test('supports RGBO construction', () {
      expect(
        Color.fromRGBO(255, 0, 0, 0.5),
        const Color.fromARGB(128, 255, 0, 0),
      );
    });

    test('provides the extended named palette', () {
      expect(Colors.pink, const Color(0xE91E63));
      expect(Colors.teal, const Color(0x009688));
      expect(Colors.orange, const Color(0xFF9800));
      expect(Colors.blueGray, Colors.blueGrey);
    });
  });
}
