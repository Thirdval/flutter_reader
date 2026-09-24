import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String idOf(String s) => s;

  List<String> apply(List<String> old, ItemDiff<String> d) {
    final list = [...old];
    for (final op in d.ops) {
      switch (op) {
        case RemoveItems<String>(:final start, :final count):
          list.removeRange(start, start + count);
        case InsertItems<String>(:final index, :final items):
          list.insertAll(index, items);
      }
    }
    return list;
  }

  test('a single move re-inserts only the moved item', () {
    final old = ['a', 'b', 'c', 'd', 'e'];
    final next = ['a', 'c', 'd', 'b', 'e'];
    final d = diffItems<String>(oldIds: old, newItems: next, idOf: idOf);
    expect(d.ops, [
      isA<RemoveItems<String>>()
          .having((o) => o.start, 'start', 1)
          .having((o) => o.count, 'count', 1),
      isA<InsertItems<String>>().having((o) => o.index, 'index', 3),
    ]);
    expect(apply(old, d), next);
  });

  test('a swap at the end moves one item', () {
    final old = [for (var i = 0; i < 100; i++) 'm$i'];
    final next = [...old];
    next[98] = old[99];
    next[99] = old[98];
    final d = diffItems<String>(oldIds: old, newItems: next, idOf: idOf);
    expect(d.ops.length, 2);
    expect(apply(old, d), next);
  });

  test('a full reversal still converges', () {
    final old = [for (var i = 0; i < 50; i++) 'm$i'];
    final next = old.reversed.toList();
    final d = diffItems<String>(oldIds: old, newItems: next, idOf: idOf);
    expect(apply(old, d), next);
  });

  test('random permutations with inserts and removals converge', () {
    var seed = 12345;
    int rand(int max) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % max;
    }

    var counter = 1000;
    for (var trial = 0; trial < 200; trial++) {
      final old = [for (var i = 0; i < 30; i++) 'x${trial}_$i'];
      final next = [...old];
      for (var k = 0; k < 5; k++) {
        switch (rand(3)) {
          case 0:
            if (next.isNotEmpty) next.removeAt(rand(next.length));
          case 1:
            next.insert(rand(next.length + 1), 'n${counter++}');
          case _:
            if (next.length > 1) {
              final item = next.removeAt(rand(next.length));
              next.insert(rand(next.length + 1), item);
            }
        }
      }
      final d = diffItems<String>(oldIds: old, newItems: next, idOf: idOf);
      expect(apply(old, d), next, reason: 'trial $trial');
    }
  });
}
