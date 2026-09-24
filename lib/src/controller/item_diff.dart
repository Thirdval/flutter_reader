/// One step of applying a new item list over an old one.
sealed class const ItemDiffOp<T>();

/// Remove [count] items from [start].
final class const RemoveItems<T>(final int start, final int count)
    extends ItemDiffOp<T>;

/// Insert [items] at [index] (an index in the list being built).
final class const InsertItems<T>(final int index, final List<T> items)
    extends ItemDiffOp<T>;

/// The ops that turn the old list into the new one, applied in order,
/// plus which edges gained items.
class const ItemDiff<T>({
  required final List<ItemDiffOp<T>> ops,
  required final bool insertedAtStart,
  required final bool insertedAtEnd,
});

/// Diffs [newItems] against [oldIds] by id. Survivors that keep their
/// relative order stay in place (a longest increasing subsequence of
/// their new positions); the others are removed and inserted again.
/// Removals come first, from the end, so earlier indices stay valid;
/// then insertions in ascending order of their final index.
ItemDiff<T> diffItems<T>({
  required List<String> oldIds,
  required List<T> newItems,
  required String Function(T item) idOf,
}) {
  final newIndexById = <String, int>{
    for (var i = 0; i < newItems.length; i++) idOf(newItems[i]): i,
  };
  assert(
    newIndexById.length == newItems.length,
    'diffItems: duplicate ids in the new items',
  );

  // Survivors in old order with their new positions; those on a longest
  // increasing subsequence stay, the rest move.
  final survivors = <String>[];
  final positions = <int>[];
  for (final id in oldIds) {
    if (newIndexById[id] case final index?) {
      survivors.add(id);
      positions.add(index);
    }
  }
  final stay = <String>{
    for (final at in _longestIncreasingSubsequence(positions)) survivors[at],
  };

  final ops = <ItemDiffOp<T>>[];
  final removals = <RemoveItems<T>>[];
  var runStart = -1;
  var runLength = 0;
  for (var i = 0; i <= oldIds.length; i++) {
    final gone = i < oldIds.length && !stay.contains(oldIds[i]);
    if (gone) {
      if (runStart < 0) runStart = i;
      runLength++;
    } else if (runStart >= 0) {
      removals.add(RemoveItems<T>(runStart, runLength));
      runStart = -1;
      runLength = 0;
    }
  }
  ops.addAll(removals.reversed);

  var insertStart = -1;
  var run = <T>[];
  for (var i = 0; i <= newItems.length; i++) {
    final fresh = i < newItems.length && !stay.contains(idOf(newItems[i]));
    if (fresh) {
      if (insertStart < 0) insertStart = i;
      run.add(newItems[i]);
    } else if (insertStart >= 0) {
      ops.add(InsertItems<T>(insertStart, run));
      insertStart = -1;
      run = <T>[];
    }
  }
  return ItemDiff<T>(
    ops: ops,
    insertedAtStart:
        newItems.isNotEmpty && !stay.contains(idOf(newItems.first)),
    insertedAtEnd: newItems.isNotEmpty && !stay.contains(idOf(newItems.last)),
  );
}

/// The positions (into [values]) of one longest strictly increasing
/// subsequence, ascending. O(n log n) patience sorting.
List<int> _longestIncreasingSubsequence(List<int> values) {
  if (values.isEmpty) return const [];
  final tails = <int>[]; // positions of the smallest tail per length
  final previous = List<int>.filled(values.length, -1);
  for (var i = 0; i < values.length; i++) {
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[tails[mid]] < values[i]) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) previous[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final result = <int>[];
  for (var at = tails.last; at >= 0; at = previous[at]) {
    result.add(at);
  }
  return result.reversed.toList();
}
