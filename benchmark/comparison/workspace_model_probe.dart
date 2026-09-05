// Untimed model parity helper. The measured terminal adapter does not use this.
import 'dart:convert';
import 'dart:io';

import 'workspace.dart';

void main(List<String> arguments) {
  final spec =
      jsonDecode(File(arguments.single).readAsStringSync())
          as Map<String, dynamic>;
  final model = Workspace(spec);
  final sourceRow = (spec['records'] as List).first as Map<String, dynamic>;
  final initialText = model.text();
  final originalService = sourceRow['service'];
  sourceRow['service'] = 'changed after decoding';
  final ownsDecodedRows = model.text() == initialText;
  sourceRow['service'] = originalService;
  stdout.writeln(jsonEncode({'owns_decoded_rows': ownsDecodedRows}));

  void snapshot() {
    stdout.writeln(
      jsonEncode({
        'text': model.text(),
        'selected': model.selected.toList()..sort(),
        'record_count': model.records.length,
        'matches': model.matches.map((row) => row.id).toList(),
      }),
    );
  }

  snapshot();
  for (final key in (spec['actions'] as List).cast<String>()) {
    if (!model.apply(key)) throw StateError('Unknown action $key');
    snapshot();
  }
}
