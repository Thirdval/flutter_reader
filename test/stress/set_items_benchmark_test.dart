/// The cost of handing the controller a whole list again: one edit, one
/// removal, one move, at 500 and 5,000 items.
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  test('setItems with one change stays cheap at 500 and 5,000 items', () {
    for (final n in [500, 5000]) {
      final controller = controllerOf(items(n));
      double time(void Function() body, {int repeat = 20}) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < repeat; i++) {
          body();
        }
        return watch.elapsedMicroseconds / repeat;
      }

      final edit = time(() {
        final list = controller.items.toList();
        list[n ~/ 2] = Item(list[n ~/ 2].n, type: 'divider');
        controller.setItems(list);
      });
      var fresh = 100000;
      final removeAndAdd = time(() {
        final list = controller.items.toList()..removeAt(n ~/ 3);
        list.add(Item(fresh++));
        controller.setItems(list);
      });
      final move = time(() {
        final list = controller.items.toList();
        final moved = list.removeAt(n - 2);
        list.insert(n - 10, moved);
        controller.setItems(list);
      });
      final unchanged = time(
        () => controller.setItems(controller.items.toList()),
      );
      // ignore: avoid_print
      print(
        'setItems n=$n: unchanged ${unchanged.toStringAsFixed(0)} µs, edit '
        '${edit.toStringAsFixed(0)} µs, remove+add ${removeAndAdd.toStringAsFixed(0)} µs, '
        'move ${move.toStringAsFixed(0)} µs',
      );
      expect(edit, lessThan(n == 500 ? 5000 : 40000));
      expect(move, lessThan(n == 500 ? 5000 : 40000));
      controller.dispose();
    }
  }, tags: ['benchmark']);
}
