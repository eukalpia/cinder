import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('renderPlainWidget produces text without an interactive terminal',
      () async {
    final result = await renderPlainWidget(
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[Text('status: healthy'), Text('requests: 42')],
      ),
      size: const Size(32, 6),
    );

    expect(result.text, contains('status: healthy'));
    expect(result.text, contains('requests: 42'));
    expect(result.toJson()['width'], 32);
    expect(CinderBinding.hasInstance, isFalse);
  });
}
