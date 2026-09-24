import '../core/chunked_height_index.dart';
import '../model/height_entry.dart';
import '../model/item_type_config.dart';
import '../model/reader_item.dart';

/// The ordered list of items with their heights: an id → bucket map
/// over a [ChunkedHeightIndex]. Appends are O(1), a mid-list insert
/// O(B + log(N/B)); ids are unique within a registry.
class ItemRegistry<T>._({
  required final Map<String, ItemTypeConfig<T>> _typeConfigs,
  required final Map<String, Bucket> _idToBucket,
  required final ChunkedHeightIndex _heightIndex,
  required var double _currentWidth,
}) {
  /// Builds a registry from [items] at [initialWidth]. Every item's
  /// `typeKey` needs an entry in [typeConfigs] (asserted in debug; a
  /// 50 px / 0.1 fallback in release) and ids must be unique.
  factory build({
    required List<ReaderItem<T>> items,
    required Map<String, ItemTypeConfig<T>> typeConfigs,
    required double initialWidth,
    int bucketSize = 128,
  }) {
    assert(_uniqueIds(items), 'ItemRegistry: duplicate item ids');
    final entries = <HeightEntry>[
      for (final item in items)
        _entryFor(item, typeConfigs[item.typeKey], initialWidth),
    ];
    final registry = ItemRegistry<T>._(
      typeConfigs: typeConfigs,
      idToBucket: {},
      heightIndex: ChunkedHeightIndex.build(
        entries,
        targetBucketSize: bucketSize,
        data: List<Object?>.of(items),
      ),
      currentWidth: initialWidth,
    );
    registry._refreshBucketMap();
    return registry;
  }

  // ── Queries ──────────────────────────────────────────────────────────

  int get itemCount => _heightIndex.itemCount;
  double get totalHeight => _heightIndex.totalHeight;
  double get currentWidth => _currentWidth;
  ChunkedHeightIndex get heightIndex => _heightIndex;

  ReaderItem<T> itemAt(int index) =>
      _heightIndex.dataAt(index) as ReaderItem<T>;

  String idAt(int index) => itemAt(index).id;

  bool containsId(String id) => _idToBucket.containsKey(id);

  /// The global index of [id], or null. O(1) map + O(B) bucket scan.
  int? indexOfId(String id) => locateById(id)?.index;

  double offsetOfIndex(int index) => _heightIndex.offsetOfItem(index);

  /// The pixel offset of [id], or null.
  double? offsetOfId(String id) => locateById(id)?.offset;

  /// Index and offset of [id] from one bucket scan, or null.
  ({int index, double offset})? locateById(String id) {
    final bucket = _idToBucket[id];
    if (bucket == null) return null;
    for (var i = 0; i < bucket.length; i++) {
      if (bucket.dataAt(i) case ReaderItem<T>(id: final found)
          when found == id) {
        return (
          index: _heightIndex.bucketStartAt(bucket.bucketIndex) + i,
          offset:
              _heightIndex.offsetOfBucketStart(bucket.bucketIndex) +
              bucket.localOffset(i),
        );
      }
    }
    return null;
  }

  int itemIndexAtOffset(double pixelOffset) =>
      _heightIndex.itemAtOffset(pixelOffset);

  (int first, int last) visibleRange(
    double scrollOffset,
    double viewportHeight,
  ) => _heightIndex.visibleRange(scrollOffset, viewportHeight);

  HeightEntry heightEntryAt(int index) => _heightIndex.entryAt(index);

  double heightAt(int index) => _heightIndex.heightAt(index);

  double get averageConfidence => _heightIndex.averageConfidence;

  List<int> lowConfidenceItems({double threshold = 0.5, int limit = 100}) =>
      _heightIndex.lowConfidenceItems(threshold: threshold, limit: limit);

  double estimatedJumpError(int from, int to) =>
      _heightIndex.estimatedJumpError(from, to);

  ItemTypeConfig<T>? typeConfigFor(String typeKey) => _typeConfigs[typeKey];

  WidthSensitivity sensitivityAt(int index) =>
      _typeConfigs[itemAt(index).typeKey]?.widthSensitivity ??
      WidthSensitivity.dependent;

  // ── Mutations ────────────────────────────────────────────────────────

  /// Records a rendered height (tier measured); returns the delta.
  double reportMeasuredHeight(int index, double measuredHeight) =>
      _heightIndex.updateHeight(
        index,
        newHeight: measuredHeight,
        tier: HeightTier.measured,
        confidence: 1,
        measuredAtWidth: _currentWidth,
      );

  /// Records a content-aware estimate (tier premeasured); returns the
  /// delta. A measured item is never downgraded.
  double reportEstimatedHeight(
    int index,
    double height, {
    double confidence = 0.9,
  }) {
    if (_heightIndex.entryAt(index).tier == HeightTier.measured) return 0;
    return _heightIndex.updateHeight(
      index,
      newHeight: height,
      tier: HeightTier.premeasured,
      confidence: confidence,
      measuredAtWidth: _currentWidth,
    );
  }

  /// Replaces the item at [index] with [item], keeping its height.
  void setItem(int index, ReaderItem<T> item) {
    final old = itemAt(index);
    if (old.id != item.id) {
      assert(!containsId(item.id), 'ItemRegistry: duplicate id "${item.id}"');
      final loc = _heightIndex.locateItem(index);
      _idToBucket
        ..remove(old.id)
        ..[item.id] = _heightIndex.bucketAt(loc.bucketIndex);
    }
    _heightIndex.setDataAt(index, item);
  }

  void insert(int index, ReaderItem<T> item, {double? estimatedHeight}) {
    assert(!containsId(item.id), 'ItemRegistry: duplicate id "${item.id}"');
    final before = _heightIndex.bucketCount;
    _heightIndex.insert(
      index,
      _buildHeightEntry(item, estimatedHeight: estimatedHeight),
      data: item,
    );
    if (_heightIndex.bucketCount != before) {
      _refreshBucketMap();
    } else {
      final loc = _heightIndex.locateItem(index);
      _idToBucket[item.id] = _heightIndex.bucketAt(loc.bucketIndex);
    }
  }

  void removeAt(int index) {
    final removed = itemAt(index);
    final before = _heightIndex.bucketCount;
    _heightIndex.removeAt(index);
    _idToBucket.remove(removed.id);
    if (_heightIndex.bucketCount != before) _refreshBucketMap();
  }

  /// Inserts [items] at [index] in one pass; O(n + k) for large batches.
  void insertAll(
    int index,
    List<ReaderItem<T>> items, {
    List<double?>? estimatedHeights,
  }) {
    if (items.isEmpty) return;
    assert(
      _uniqueIds(items) && !items.any((i) => containsId(i.id)),
      'ItemRegistry: duplicate item ids',
    );
    _heightIndex.insertAll(index, [
      for (var i = 0; i < items.length; i++)
        _buildHeightEntry(items[i], estimatedHeight: estimatedHeights?[i]),
    ], data: List<Object?>.of(items));
    _refreshBucketMap();
  }

  /// Removes [count] items from [startIndex] on.
  void removeRange(int startIndex, int count) {
    if (count <= 0) return;
    for (var i = startIndex; i < startIndex + count; i++) {
      _idToBucket.remove(idAt(i));
    }
    _heightIndex.removeRange(startIndex, count);
    _refreshBucketMap();
  }

  /// Re-estimates every height for [newWidth] by type sensitivity;
  /// [viewportRange] first. Returns the changed indices.
  List<int> onWidthChanged(double newWidth, {(int, int)? viewportRange}) {
    final oldWidth = _currentWidth;
    _currentWidth = newWidth;
    return _heightIndex.onWidthChanged(
      newWidth: newWidth,
      prioritizeRange: viewportRange,
      recomputeHeight: (globalIndex, current) {
        final item = itemAt(globalIndex);
        final config = _typeConfigs[item.typeKey];
        final unchanged = (
          height: current.height,
          confidence: current.confidence,
        );
        if (config == null) return unchanged;
        return switch (config) {
          ItemTypeConfig<T>(widthSensitivity: WidthSensitivity.invariant) =>
            unchanged,
          ItemTypeConfig<T>(
            widthSensitivity: WidthSensitivity.proportional,
            proportionalHeightFn: final fn?,
          ) =>
            (height: fn(item.data, newWidth), confidence: 0.99),
          ItemTypeConfig<T>(widthSensitivity: WidthSensitivity.proportional) =>
            unchanged,
          ItemTypeConfig<T>(estimator: final estimator?) => estimator(
            item.data,
            newWidth,
          ),
          // No estimator: scale by the width ratio at half the confidence.
          _ => (
            height: current.height * (oldWidth / newWidth),
            confidence: current.confidence * 0.5,
          ),
        };
      },
    );
  }

  // ── Private ──────────────────────────────────────────────────────────

  static bool _uniqueIds<T>(List<ReaderItem<T>> items) {
    final seen = <String>{};
    return items.every((item) => seen.add(item.id));
  }

  static HeightEntry _entryFor<T>(
    ReaderItem<T> item,
    ItemTypeConfig<T>? config,
    double width,
  ) {
    assert(
      config != null,
      'ItemRegistry: no ItemTypeConfig for typeKey "${item.typeKey}" '
      '(item "${item.id}")',
    );
    if (config == null) return HeightEntry(height: 50, confidence: 0.1);
    if (config.estimator case final estimator?) {
      final est = estimator(item.data, width);
      return HeightEntry(
        height: est.height,
        tier: HeightTier.premeasured,
        confidence: est.confidence,
        measuredAtWidth: width,
      );
    }
    if (config case ItemTypeConfig<T>(
      widthSensitivity: WidthSensitivity.proportional,
      proportionalHeightFn: final fn?,
    )) {
      return HeightEntry(
        height: fn(item.data, width),
        tier: HeightTier.premeasured,
        confidence: 0.99,
        measuredAtWidth: width,
      );
    }
    return HeightEntry(
      height: config.defaultHeight,
      confidence: config.defaultConfidence,
      measuredAtWidth: width,
    );
  }

  HeightEntry _buildHeightEntry(ReaderItem<T> item, {double? estimatedHeight}) {
    if (estimatedHeight != null) {
      return HeightEntry(height: estimatedHeight, confidence: 0.5);
    }
    return _entryFor(item, _typeConfigs[item.typeKey], _currentWidth);
  }

  /// Rebuilds the id map from the buckets. O(n).
  void _refreshBucketMap() {
    _idToBucket.clear();
    _heightIndex.forEachItemWithBucket((_, data, bucket) {
      _idToBucket[(data as ReaderItem<T>).id] = bucket;
    });
  }
}
