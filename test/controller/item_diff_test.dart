import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String idOf(String s) => s;

  ItemDiff<String> diff(List<String> old, List<String> next) =>
      diffItems<String>(oldIds: old, newItems: next, idOf: idOf);

  /// Applies [d] to [old] the way the controller does.
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

  test('prepend', () {
    final d = diff(['c', 'd'], ['a', 'b', 'c', 'd']);
    expect(d.ops, [isA<InsertItems<String>>()]);
    expect(d.insertedAtStart, isTrue);
    expect(d.insertedAtEnd, isFalse);
    expect(apply(['c', 'd'], d), ['a', 'b', 'c', 'd']);
  });

  test('append', () {
    final d = diff(['a'], ['a', 'b']);
    expect(d.insertedAtStart, isFalse);
    expect(d.insertedAtEnd, isTrue);
    expect(apply(['a'], d), ['a', 'b']);
  });

  test('removals in ranges, from the end', () {
    final old = ['a', 'b', 'c', 'd', 'e', 'f'];
    final d = diff(old, ['a', 'd', 'f']);
    expect(d.ops, [
      isA<RemoveItems<String>>().having((o) => o.start, 'start', 4),
      isA<RemoveItems<String>>().having((o) => o.start, 'start', 1),
    ]);
    expect(apply(old, d), ['a', 'd', 'f']);
  });

  test('mixed inserts and removals keep survivors', () {
    final old = ['a', 'b', 'c', 'd'];
    final next = ['x', 'a', 'c', 'y', 'z', 'd', 'w'];
    final d = diff(old, next);
    expect(apply(old, d), next);
    expect(d.insertedAtStart, isTrue);
    expect(d.insertedAtEnd, isTrue);
  });

  test('a reorder moves the fewest items', () {
    final d = diff(['a', 'b', 'c'], ['a', 'c', 'b']);
    expect(d.ops.length, 2);
    expect(apply(['a', 'b', 'c'], d), ['a', 'c', 'b']);
  });

  test('identical lists produce no ops', () {
    final d = diff(['a', 'b'], ['a', 'b']);
    expect(d.ops, isEmpty);
    expect(d.insertedAtStart, isFalse);
    expect(d.insertedAtEnd, isFalse);
  });

  test('empty to something and back', () {
    expect(apply([], diff([], ['a', 'b'])), ['a', 'b']);
    expect(apply(['a', 'b'], diff(['a', 'b'], [])), isEmpty);
  });
}
