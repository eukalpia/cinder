import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('WidgetStateMapper chooses the most specific matching state set', () {
    final property = WidgetStateMapper<String>(
      <Set<WidgetState>, String>{
        <WidgetState>{WidgetState.hovered}: 'hovered',
        <WidgetState>{WidgetState.hovered, WidgetState.focused}: 'active',
        <WidgetState>{WidgetState.disabled}: 'disabled',
      },
      fallback: 'idle',
    );

    expect(property.resolve(const <WidgetState>{}), 'idle');
    expect(property.resolve(<WidgetState>{WidgetState.hovered}), 'hovered');
    expect(
      property.resolve(<WidgetState>{WidgetState.hovered, WidgetState.focused}),
      'active',
    );
  });

  test('WidgetStatesController reports meaningful transitions only', () {
    final controller = WidgetStatesController();
    expect(controller.update(WidgetState.focused, true), isTrue);
    expect(controller.update(WidgetState.focused, true), isFalse);
    expect(controller.contains(WidgetState.focused), isTrue);
    expect(controller.update(WidgetState.focused, false), isTrue);
  });
}
