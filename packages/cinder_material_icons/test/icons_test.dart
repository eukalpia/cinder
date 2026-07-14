import 'package:cinder_material_icons/cinder_material_icons.dart';
import 'package:test/test.dart';

void main() {
  test('material catalog exposes Flutter-style names', () {
    expect(Icons.home.name, 'home');
    expect(Icons.arrow_back.matchTextDirection, isTrue);
    expect(Icons.count, greaterThan(1000));
  });
}
