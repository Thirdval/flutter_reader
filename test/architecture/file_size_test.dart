/// Size caps, as in Tendvine's presentation standard §5: engine files
/// (pure data structures) stay under 500 lines, everything else under
/// 400. There is no ledger; a file over the cap splits by concern.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _engineCap = 500;
const _cap = 400;

void main() {
  test('library files stay under the size caps', () {
    final over = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final cap = file.path.contains('/engine/') ? _engineCap : _cap;
      final lines = file.readAsLinesSync().length;
      if (lines > cap) over.add('${file.path}: $lines > $cap');
    }
    expect(over, isEmpty, reason: 'Over the size cap:\n${over.join('\n')}');
  });
}
