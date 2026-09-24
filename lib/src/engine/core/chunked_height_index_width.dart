part of 'chunked_height_index.dart';

/// Width-change recomputation and diagnostics of a [ChunkedHeightIndex].
extension ChunkedHeightIndexWidth on ChunkedHeightIndex {
  /// Recomputes every height for [newWidth] through [recomputeHeight],
  /// the [prioritizeRange] first. Incremental Fenwick updates: O(k log B)
  /// for k changed items. Returns the changed global indices.
  List<int> onWidthChanged({
    required double newWidth,
    required HeightEstimate Function(int globalIndex, HeightEntry current)
    recomputeHeight,
    (int start, int end)? prioritizeRange,
  }) {
    final changed = <int>[];
    final reusable = HeightEntry(height: 0);
    var rangeStart = 0;
    var rangeEnd = -1;
    if (prioritizeRange != null && _totalItems > 0) {
      rangeStart = prioritizeRange.$1.clamp(0, _totalItems - 1);
      rangeEnd = prioritizeRange.$2.clamp(0, _totalItems - 1);
      for (var i = rangeStart; i <= rangeEnd; i++) {
        final loc = locateItem(i);
        _recompute(
          i,
          loc.bucketIndex,
          loc.localIndex,
          reusable,
          recomputeHeight,
          newWidth,
          changed,
        );
      }
    }
    var globalIndex = 0;
    for (var bi = 0; bi < _buckets.length; bi++) {
      final bucket = _buckets[bi];
      for (var li = 0; li < bucket.length; li++) {
        if (prioritizeRange == null ||
            globalIndex < rangeStart ||
            globalIndex > rangeEnd) {
          _recompute(
            globalIndex,
            bi,
            li,
            reusable,
            recomputeHeight,
            newWidth,
            changed,
          );
        }
        globalIndex++;
      }
    }
    return changed;
  }

  /// Recomputes the heights of [indices] only.
  List<int> batchReestimate(
    List<int> indices,
    HeightEstimate Function(int globalIndex, HeightEntry current)
    recomputeHeight,
    double atWidth,
  ) {
    final changed = <int>[];
    final reusable = HeightEntry(height: 0);
    for (final globalIndex in indices) {
      if (globalIndex < 0 || globalIndex >= _totalItems) continue;
      final loc = locateItem(globalIndex);
      _recompute(
        globalIndex,
        loc.bucketIndex,
        loc.localIndex,
        reusable,
        recomputeHeight,
        atWidth,
        changed,
      );
    }
    return changed;
  }

  /// The global indices of up to [limit] items below [threshold]
  /// confidence, least confident first. O(n): a diagnostic.
  List<int> lowConfidenceItems({double threshold = 0.5, int limit = 100}) {
    final candidates = <(int, double)>[];
    var globalIndex = 0;
    for (final bucket in _buckets) {
      for (var i = 0; i < bucket.length; i++) {
        final conf = bucket.confidenceAt(i);
        if (conf < threshold) candidates.add((globalIndex, conf));
        globalIndex++;
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final c in candidates.take(limit)) c.$1];
  }

  /// The mean confidence over all items (1.0 when empty). O(n).
  double get averageConfidence {
    if (_totalItems == 0) return 1;
    var sum = 0.0;
    for (final bucket in _buckets) {
      for (var i = 0; i < bucket.length; i++) {
        sum += bucket.confidenceAt(i);
      }
    }
    return sum / _totalItems;
  }

  void _recompute(
    int globalIndex,
    int bucketIndex,
    int localIndex,
    HeightEntry reusable,
    HeightEstimate Function(int globalIndex, HeightEntry current) recompute,
    double width,
    List<int> changed,
  ) {
    final bucket = _buckets[bucketIndex];
    bucket.fillEntry(localIndex, reusable);
    final result = recompute(globalIndex, reusable);
    if ((result.height - bucket.heightAt(localIndex)).abs() <= 0.01) return;
    final delta = bucket.updateHeight(
      localIndex,
      result.height,
      HeightTier.premeasured,
      result.confidence,
      width,
    );
    _fenwick.update(bucketIndex, delta.height);
    _errorFenwick.update(bucketIndex, delta.error);
    changed.add(globalIndex);
  }
}
