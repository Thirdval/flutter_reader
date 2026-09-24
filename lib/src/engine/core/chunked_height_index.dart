import 'dart:math';
import 'dart:typed_data';

import '../model/height_entry.dart';
import '../model/item_type_config.dart';
import 'fenwick_tree.dart';

part 'bucket.dart';
part 'chunked_height_index_width.dart';

/// A bucket index plus a local index within it.
class const ItemLocation({
  required final int bucketIndex,
  required final int localIndex,
});

/// A two-level index over a dynamic list of item heights: buckets of
/// about [targetBucketSize] items (level 1) under a Fenwick tree of
/// bucket totals (level 2). Prefix sums, reverse lookups, updates,
/// inserts and removals cost O(B + log(N/B)). A second Fenwick tree
/// over per-bucket jump error makes [estimatedJumpError] the same.
///
/// Per-item payloads are stored beside the heights so a mid-list
/// insert shifts O(B) entries, not the whole list.
class ChunkedHeightIndex._({
  required final int targetBucketSize,
  required final List<Bucket> _buckets,
  required var FenwickTree _fenwick,
  required var FenwickTree _errorFenwick,
  required var Int32List _bucketStarts,
  required var int _totalItems,
}) {
  /// Builds an index from [entries] and optional parallel [data].
  factory build(
    List<HeightEntry> entries, {
    int targetBucketSize = 128,
    List<Object?>? data,
  }) {
    final index = ChunkedHeightIndex._(
      targetBucketSize: targetBucketSize,
      buckets: [],
      fenwick: FenwickTree(0),
      errorFenwick: FenwickTree(0),
      bucketStarts: Int32List(0),
      totalItems: 0,
    );
    if (entries.isNotEmpty) {
      index._rebuildFromAll(
        entries,
        data ?? List<Object?>.filled(entries.length, null),
      );
    }
    return index;
  }

  // ── Queries ──────────────────────────────────────────────────────────

  int get itemCount => _totalItems;
  double get totalHeight => _fenwick.totalSum;
  int get bucketCount => _buckets.length;

  Bucket bucketAt(int bi) => _buckets[bi];

  /// The pixel offset where bucket [bi] starts.
  double offsetOfBucketStart(int bi) => bi > 0 ? _fenwick.prefixSum(bi - 1) : 0;

  /// The global index where bucket [bi] starts.
  int bucketStartAt(int bi) => _bucketStarts[bi];

  /// Locates [globalIndex] by binary search over the bucket starts.
  ItemLocation locateItem(int globalIndex) {
    assert(
      globalIndex >= 0 && globalIndex < _totalItems,
      'Index $globalIndex out of range [0, $_totalItems)',
    );
    var lo = 0;
    var hi = _buckets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_bucketStarts[mid] <= globalIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return ItemLocation(
      bucketIndex: lo,
      localIndex: globalIndex - _bucketStarts[lo],
    );
  }

  double offsetOfItem(int globalIndex, {ItemLocation? hint}) {
    final loc = hint ?? locateItem(globalIndex);
    return offsetOfBucketStart(loc.bucketIndex) +
        _buckets[loc.bucketIndex].localOffset(loc.localIndex);
  }

  /// The item containing [pixelOffset]; -1 beyond the end, 0 before 0.
  int itemAtOffset(double pixelOffset) {
    if (_totalItems == 0) return -1;
    if (pixelOffset < 0) return 0;
    if (pixelOffset >= totalHeight) return -1;
    final bucketIndex = _fenwick.findItemAtOffset(pixelOffset);
    final localOffset = pixelOffset - offsetOfBucketStart(bucketIndex);
    return _bucketStarts[bucketIndex] +
        _buckets[bucketIndex].findLocal(localOffset);
  }

  HeightEntry entryAt(int globalIndex, {ItemLocation? hint}) {
    final loc = hint ?? locateItem(globalIndex);
    return _buckets[loc.bucketIndex].entryAt(loc.localIndex);
  }

  double heightAt(int globalIndex, {ItemLocation? hint}) {
    final loc = hint ?? locateItem(globalIndex);
    return _buckets[loc.bucketIndex].heightAt(loc.localIndex);
  }

  Object? dataAt(int globalIndex, {ItemLocation? hint}) {
    final loc = hint ?? locateItem(globalIndex);
    return _buckets[loc.bucketIndex].dataAt(loc.localIndex);
  }

  /// Replaces the payload at [globalIndex]; the height is untouched.
  void setDataAt(int globalIndex, Object? data) {
    final loc = locateItem(globalIndex);
    _buckets[loc.bucketIndex].setDataAt(loc.localIndex, data);
  }

  /// The first and last item intersecting the viewport, or `(-1, -1)`.
  (int first, int last) visibleRange(
    double scrollOffset,
    double viewportHeight,
  ) {
    final first = itemAtOffset(scrollOffset);
    if (first == -1) return (-1, -1);
    final last = itemAtOffset(scrollOffset + viewportHeight);
    return (first, last == -1 ? _totalItems - 1 : last);
  }

  /// The summed jump error over `[from, to)` (either order): the height
  /// times `1 − confidence` of every unmeasured item in between. Whole
  /// buckets come from the error tree, so the cost is O(B + log(N/B)).
  double estimatedJumpError(int fromIndex, int toIndex) {
    if (_totalItems == 0) return 0;
    final lo = min(fromIndex, toIndex).clamp(0, _totalItems - 1);
    final hi = max(fromIndex, toIndex).clamp(0, _totalItems);
    if (lo >= hi) return 0;
    final a = locateItem(lo);
    final b = locateItem(hi - 1);
    if (a.bucketIndex == b.bucketIndex) {
      return _buckets[a.bucketIndex].errorInRange(a.localIndex, b.localIndex);
    }
    var error = _buckets[a.bucketIndex].errorInRange(
      a.localIndex,
      _buckets[a.bucketIndex].length - 1,
    );
    if (b.bucketIndex - a.bucketIndex > 1) {
      error += _errorFenwick.rangeSum(a.bucketIndex + 1, b.bucketIndex - 1);
    }
    return error + _buckets[b.bucketIndex].errorInRange(0, b.localIndex);
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Updates one height; returns the height delta.
  double updateHeight(
    int globalIndex, {
    required double newHeight,
    required HeightTier tier,
    required double confidence,
    double? measuredAtWidth,
    ItemLocation? hint,
  }) {
    final loc = hint ?? locateItem(globalIndex);
    final delta = _buckets[loc.bucketIndex].updateHeight(
      loc.localIndex,
      newHeight,
      tier,
      confidence,
      measuredAtWidth,
    );
    if (delta.height != 0) _fenwick.update(loc.bucketIndex, delta.height);
    if (delta.error != 0) _errorFenwick.update(loc.bucketIndex, delta.error);
    return delta.height;
  }

  void insert(int globalIndex, HeightEntry entry, {Object? data}) {
    if (_buckets.isEmpty) {
      _rebuildFromAll([entry], [data]);
      return;
    }
    final loc = _locateItemForInsert(globalIndex);
    final bucket = _buckets[loc.bucketIndex];
    final added = bucket.insert(loc.localIndex, entry, data: data);
    _fenwick.update(loc.bucketIndex, added.height);
    _errorFenwick.update(loc.bucketIndex, added.error);
    _totalItems++;
    if (bucket.length > targetBucketSize * 2) _splitBucket(loc.bucketIndex);
    _rebuildBucketStarts();
  }

  void removeAt(int globalIndex) {
    assert(globalIndex >= 0 && globalIndex < _totalItems);
    final loc = locateItem(globalIndex);
    final bucket = _buckets[loc.bucketIndex];
    final removed = bucket.removeAt(loc.localIndex);
    _fenwick.update(loc.bucketIndex, -removed.height);
    _errorFenwick.update(loc.bucketIndex, -removed.error);
    _totalItems--;
    if (bucket.length < targetBucketSize ~/ 2 && _buckets.length > 1) {
      _tryMergeBucket(loc.bucketIndex);
    }
    if (bucket.length == 0 && _buckets.contains(bucket)) {
      _buckets.remove(bucket);
      _rebuildFenwick();
    }
    _rebuildBucketStarts();
  }

  /// Inserts [entries] at [globalIndex]; batches larger than a bucket
  /// rebuild the whole index in O(n + k).
  void insertAll(
    int globalIndex,
    List<HeightEntry> entries, {
    List<Object?>? data,
  }) {
    if (entries.isEmpty) return;
    if (entries.length > targetBucketSize) {
      final all = _extractAll();
      all.entries.insertAll(globalIndex, entries);
      all.data.insertAll(
        globalIndex,
        data ?? List<Object?>.filled(entries.length, null),
      );
      _rebuildFromAll(all.entries, all.data);
      return;
    }
    for (var i = 0; i < entries.length; i++) {
      insert(globalIndex + i, entries[i], data: data?[i]);
    }
  }

  /// Removes [count] items from [startIndex] on.
  void removeRange(int startIndex, int count) {
    if (count <= 0) return;
    if (count > targetBucketSize) {
      final all = _extractAll();
      all.entries.removeRange(startIndex, startIndex + count);
      all.data.removeRange(startIndex, startIndex + count);
      _rebuildFromAll(all.entries, all.data);
      return;
    }
    for (var i = count - 1; i >= 0; i--) {
      removeAt(startIndex + i);
    }
  }

  // ── Iteration ────────────────────────────────────────────────────────

  /// Visits every item in order with its payload. O(n).
  void forEachData(void Function(int globalIndex, Object? data) callback) {
    var globalIndex = 0;
    for (final bucket in _buckets) {
      for (var i = 0; i < bucket.length; i++) {
        callback(globalIndex, bucket.dataAt(i));
        globalIndex++;
      }
    }
  }

  /// Visits every item with its bucket, for id-map rebuilds. O(n).
  void forEachItemWithBucket(
    void Function(int globalIndex, Object? data, Bucket bucket) callback,
  ) {
    var globalIndex = 0;
    for (final bucket in _buckets) {
      for (var i = 0; i < bucket.length; i++) {
        callback(globalIndex, bucket.dataAt(i), bucket);
        globalIndex++;
      }
    }
  }

  // ── Private ──────────────────────────────────────────────────────────

  ItemLocation _locateItemForInsert(int globalIndex) {
    if (globalIndex >= _totalItems) {
      return ItemLocation(
        bucketIndex: _buckets.length - 1,
        localIndex: _buckets.last.length,
      );
    }
    return locateItem(globalIndex);
  }

  void _splitBucket(int bucketIndex) {
    final bucket = _buckets[bucketIndex];
    _buckets.insert(bucketIndex + 1, bucket.split(bucket.length ~/ 2));
    _rebuildFenwick();
  }

  void _tryMergeBucket(int bucketIndex) {
    if (_buckets.length <= 1) return;
    final bucket = _buckets[bucketIndex];
    if (bucketIndex > 0 &&
        _buckets[bucketIndex - 1].length + bucket.length <=
            targetBucketSize * 2) {
      _buckets[bucketIndex - 1].merge(bucket);
      _buckets.removeAt(bucketIndex);
      _rebuildFenwick();
    } else if (bucketIndex < _buckets.length - 1 &&
        bucket.length + _buckets[bucketIndex + 1].length <=
            targetBucketSize * 2) {
      bucket.merge(_buckets[bucketIndex + 1]);
      _buckets.removeAt(bucketIndex + 1);
      _rebuildFenwick();
    }
  }

  void _rebuildFenwick() {
    _fenwick = FenwickTree.fromList([for (final b in _buckets) b.totalHeight]);
    _errorFenwick = FenwickTree.fromList([
      for (final b in _buckets) b.totalError,
    ]);
  }

  void _rebuildBucketStarts() {
    final starts = Int32List(_buckets.length);
    var cumulative = 0;
    for (var i = 0; i < _buckets.length; i++) {
      starts[i] = cumulative;
      cumulative += _buckets[i].length;
      _buckets[i]._bucketIndex = i;
    }
    _bucketStarts = starts;
  }

  ({List<HeightEntry> entries, List<Object?> data}) _extractAll() {
    final entries = <HeightEntry>[];
    final data = <Object?>[];
    for (final bucket in _buckets) {
      for (var i = 0; i < bucket.length; i++) {
        entries.add(bucket.entryAt(i));
        data.add(bucket.dataAt(i));
      }
    }
    return (entries: entries, data: data);
  }

  void _rebuildFromAll(List<HeightEntry> entries, List<Object?> data) {
    _buckets.clear();
    _totalItems = entries.length;
    for (var i = 0; i < entries.length; i += targetBucketSize) {
      final end = min(i + targetBucketSize, entries.length);
      _buckets.add(
        Bucket.fromEntries(entries.sublist(i, end), data: data.sublist(i, end)),
      );
    }
    _rebuildFenwick();
    _rebuildBucketStarts();
  }
}
