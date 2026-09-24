/// One step of applying a new item list over an old one.
sealed class const ItemDiffOp<T>();

/// Remove [count] items from [start].
final class const RemoveItems<T>(final int start, final int count)
    extends ItemDiffOp<T>;

/// Insert [items] at [index] (an index in the list being built).
final class const InsertItems<T>(final int index, final List<T> items)
    extends ItemDiffOp<T>;

/// The surviving items changed order: rebuild from scratch.
final class const ReplaceAll<T>(final List<T> items) extends ItemDiffOp<T>;

/// The ops that turn the old list into the new one, applied in order,
/// plus which edges gained items.
class const ItemDiff<T>({
  required final List<ItemDiffOp<T>> ops,
  required final bool insertedAtStart,
  required final bool insertedAtEnd,
});

/// Diffs [newItems] against [oldIds] by id. Removals come first (from
/// the end, so earlier indices stay valid), then insertions in
/// ascending order of their final index. Survivors must keep their
/// relative order; otherwise the whole list is replaced.
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
  final ops = <ItemDiffOp<T>>[];

  // Removals, grouped into ranges, emitted from the end.
  var runStart = -1;
  var runLength = 0;
  final removals = <RemoveItems<T>>[];
  for (var i = 0; i <= oldIds.length; i++) {
    final gone = i < oldIds.length && !newIndexById.containsKey(oldIds[i]);
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

  // Survivors must keep their relative order.
  var previous = -1;
  final oldIdSet = <String>{};
  for (final id in oldIds) {
    final index = newIndexById[id];
    if (index == null) continue;
    oldIdSet.add(id);
    if (index <= previous) {
      return ItemDiff<T>(
        ops: [ReplaceAll<T>(newItems)],
        insertedAtStart:
            newItems.isNotEmpty && !oldIds.contains(idOf(newItems.first)),
        insertedAtEnd:
            newItems.isNotEmpty && !oldIds.contains(idOf(newItems.last)),
      );
    }
    previous = index;
  }

  // Insertions, in ascending order of their final index.
  var insertStart = -1;
  var run = <T>[];
  for (var i = 0; i <= newItems.length; i++) {
    final fresh = i < newItems.length && !oldIdSet.contains(idOf(newItems[i]));
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
        newItems.isNotEmpty && !oldIdSet.contains(idOf(newItems.first)),
    insertedAtEnd:
        newItems.isNotEmpty && !oldIdSet.contains(idOf(newItems.last)),
  );
}
