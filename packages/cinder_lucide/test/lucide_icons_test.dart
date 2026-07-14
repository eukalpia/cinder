import 'package:cinder_lucide/cinder_lucide.dart';
import 'package:test/test.dart';

void main() {
  test('lucide catalog exposes generated icons', () {
    expect(LucideIcons.activity.name, 'activity');
    expect(LucideIcons.arrowLeft.matchTextDirection, isTrue);
    expect(LucideIcons.count, greaterThan(1000));
  });
}
