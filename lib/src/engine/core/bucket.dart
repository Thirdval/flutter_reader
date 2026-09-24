part of 'chunked_height_index.dart';

/// A contiguous slice of items in struct-of-arrays layout.
///
/// The hot paths ([localOffset], [findLocal]) touch only the contiguous
/// [Float64List] of heights. Per-item payloads live in a separate list
/// off the hot path. A bucket also keeps the sum of its items' jump
/// error (`height × (1 − confidence)` for unmeasured items) so the index
/// can answer [ChunkedHeightIndex.estimatedJumpError] without a scan.
class Bucket._(
  var Float64List _heights,
  var Uint8List _tiers,
  var Float64List _confidences,
  var Float64List _widths, // NaN = unknown width
  var List<Object?> _data,
  var int _length,
  var double _totalHeight,
  var double _totalError,
) {
  /// Creates a bucket from [entries] and optional parallel [data].
  factory fromEntries(List<HeightEntry> entries, {List<Object?>? data}) {
    final len = entries.length;
    final cap = max(len, _minCapacity);
    final heights = Float64List(cap);
    final tiers = Uint8List(cap);
    final confidences = Float64List(cap);
    final widths = Float64List(cap);
    final dataList = List<Object?>.filled(cap, null);
    var total = 0.0;
    var error = 0.0;
    for (var i = 0; i < len; i++) {
      final e = entries[i];
      heights[i] = e.height;
      tiers[i] = e.tier.index;
      confidences[i] = e.confidence;
      widths[i] = e.measuredAtWidth ?? double.nan;
      if (data != null) dataList[i] = data[i];
      total += e.height;
      error += _errorOf(e.height, e.tier, e.confidence);
    }
    return Bucket._(
      heights,
      tiers,
      confidences,
      widths,
      dataList,
      len,
      total,
      error,
    );
  }

  static const _minCapacity = 8;

  /// Index of this bucket within its [ChunkedHeightIndex].
  int _bucketIndex = -1;

  int get length => _length;
  double get totalHeight => _totalHeight;

  /// The sum of `height × (1 − confidence)` over unmeasured items.
  double get totalError => _totalError;
  int get bucketIndex => _bucketIndex;

  static double _errorOf(double height, HeightTier tier, double confidence) =>
      tier == HeightTier.measured ? 0 : height * (1 - confidence);

  double _errorAt(int i) =>
      _errorOf(_heights[i], HeightTier.values[_tiers[i]], _confidences[i]);

  // ── Field accessors ──────────────────────────────────────────────────

  double heightAt(int i) => _heights[i];
  HeightTier tierAt(int i) => HeightTier.values[_tiers[i]];
  double confidenceAt(int i) => _confidences[i];

  double? widthAt(int i) {
    final w = _widths[i];
    return w.isNaN ? null : w;
  }

  /// The payload stored beside the height data.
  Object? dataAt(int i) => _data[i];

  /// Replaces the payload at [i]; heights are untouched.
  void setDataAt(int i, Object? data) => _data[i] = data;

  /// A fresh [HeightEntry] for the item at [i] (not on the hot path).
  HeightEntry entryAt(int i) => HeightEntry(
    height: _heights[i],
    tier: HeightTier.values[_tiers[i]],
    confidence: _confidences[i],
    measuredAtWidth: _widths[i].isNaN ? null : _widths[i],
  );

  /// Fills [target] with the item at [i]; the allocation-free [entryAt].
  void fillEntry(int i, HeightEntry target) {
    target
      ..height = _heights[i]
      ..tier = HeightTier.values[_tiers[i]]
      ..confidence = _confidences[i]
      ..measuredAtWidth = _widths[i].isNaN ? null : _widths[i];
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Updates the item at [localIndex]; returns the height and error deltas.
  ({double height, double error}) updateHeight(
    int localIndex,
    double newHeight,
    HeightTier tier,
    double confidence,
    double? width,
  ) {
    final oldHeight = _heights[localIndex];
    final oldError = _errorAt(localIndex);
    _heights[localIndex] = newHeight;
    _tiers[localIndex] = tier.index;
    _confidences[localIndex] = confidence;
    _widths[localIndex] = width ?? double.nan;
    final height = newHeight - oldHeight;
    final error = _errorAt(localIndex) - oldError;
    _totalHeight += height;
    _totalError += error;
    return (height: height, error: error);
  }

  /// Inserts [entry] at [localIndex]; returns its height and error.
  ({double height, double error}) insert(
    int localIndex,
    HeightEntry entry, {
    Object? data,
  }) {
    if (_length == _heights.length) _grow();
    for (var i = _length; i > localIndex; i--) {
      _heights[i] = _heights[i - 1];
      _tiers[i] = _tiers[i - 1];
      _confidences[i] = _confidences[i - 1];
      _widths[i] = _widths[i - 1];
      _data[i] = _data[i - 1];
    }
    _heights[localIndex] = entry.height;
    _tiers[localIndex] = entry.tier.index;
    _confidences[localIndex] = entry.confidence;
    _widths[localIndex] = entry.measuredAtWidth ?? double.nan;
    _data[localIndex] = data;
    _length++;
    final error = _errorOf(entry.height, entry.tier, entry.confidence);
    _totalHeight += entry.height;
    _totalError += error;
    return (height: entry.height, error: error);
  }

  /// Removes the item at [localIndex]; returns its height and error.
  ({double height, double error}) removeAt(int localIndex) {
    final height = _heights[localIndex];
    final error = _errorAt(localIndex);
    for (var i = localIndex; i < _length - 1; i++) {
      _heights[i] = _heights[i + 1];
      _tiers[i] = _tiers[i + 1];
      _confidences[i] = _confidences[i + 1];
      _widths[i] = _widths[i + 1];
      _data[i] = _data[i + 1];
    }
    _data[_length - 1] = null;
    _length--;
    _totalHeight -= height;
    _totalError -= error;
    return (height: height, error: error);
  }

  // ── Queries (hot path: only touch _heights) ──────────────────────────

  double localOffset(int localIndex) {
    var sum = 0.0;
    for (var i = 0; i < localIndex; i++) {
      sum += _heights[i];
    }
    return sum;
  }

  int findLocal(double localPixelOffset) {
    var cumulative = 0.0;
    for (var i = 0; i < _length; i++) {
      if (cumulative + _heights[i] > localPixelOffset) return i;
      cumulative += _heights[i];
    }
    return _length - 1;
  }

  /// The error sum over the local range `[from, to]` inclusive.
  double errorInRange(int from, int to) {
    var sum = 0.0;
    for (var i = from; i <= to; i++) {
      sum += _errorAt(i);
    }
    return sum;
  }

  void recalculateTotals() {
    var height = 0.0;
    var error = 0.0;
    for (var i = 0; i < _length; i++) {
      height += _heights[i];
      error += _errorAt(i);
    }
    _totalHeight = height;
    _totalError = error;
  }

  /// Moves the items from [splitIndex] on into a new bucket.
  Bucket split(int splitIndex) {
    final rightLen = _length - splitIndex;
    final rightCap = max(rightLen, _minCapacity);
    final rHeights = Float64List(rightCap);
    final rTiers = Uint8List(rightCap);
    final rConfidences = Float64List(rightCap);
    final rWidths = Float64List(rightCap);
    final rData = List<Object?>.filled(rightCap, null);
    for (var i = 0; i < rightLen; i++) {
      rHeights[i] = _heights[splitIndex + i];
      rTiers[i] = _tiers[splitIndex + i];
      rConfidences[i] = _confidences[splitIndex + i];
      rWidths[i] = _widths[splitIndex + i];
      rData[i] = _data[splitIndex + i];
    }
    for (var i = splitIndex; i < _length; i++) {
      _data[i] = null;
    }
    _length = splitIndex;
    recalculateTotals();
    final right = Bucket._(
      rHeights,
      rTiers,
      rConfidences,
      rWidths,
      rData,
      rightLen,
      0,
      0,
    );
    right.recalculateTotals();
    return right;
  }

  /// Appends [other]'s items to this bucket.
  void merge(Bucket other) {
    final newLen = _length + other._length;
    if (newLen > _heights.length) _growTo(max(newLen, _heights.length * 2));
    for (var i = 0; i < other._length; i++) {
      _heights[_length + i] = other._heights[i];
      _tiers[_length + i] = other._tiers[i];
      _confidences[_length + i] = other._confidences[i];
      _widths[_length + i] = other._widths[i];
      _data[_length + i] = other._data[i];
    }
    _length = newLen;
    _totalHeight += other._totalHeight;
    _totalError += other._totalError;
  }

  void _grow() => _growTo(max(_heights.length * 2, _minCapacity));

  void _growTo(int newCapacity) {
    final newHeights = Float64List(newCapacity);
    final newTiers = Uint8List(newCapacity);
    final newConfidences = Float64List(newCapacity);
    final newWidths = Float64List(newCapacity);
    final newData = List<Object?>.filled(newCapacity, null);
    for (var i = 0; i < _length; i++) {
      newHeights[i] = _heights[i];
      newTiers[i] = _tiers[i];
      newConfidences[i] = _confidences[i];
      newWidths[i] = _widths[i];
      newData[i] = _data[i];
    }
    _heights = newHeights;
    _tiers = newTiers;
    _confidences = newConfidences;
    _widths = newWidths;
    _data = newData;
  }
}
