import 'dart:typed_data';

/// A Fenwick tree (binary indexed tree) over a list of doubles.
///
/// Point update, prefix sum and reverse lookup are O(log n); building
/// from a list is O(n). Backed by a [Float64List]; 1-indexed inside,
/// 0-indexed at the API.
class FenwickTree(var int _size) {
  /// Builds a tree from [values] in O(n).
  factory fromList(List<double> values) {
    final tree = FenwickTree(values.length);
    tree._fill(values);
    return tree;
  }

  Float64List _tree = Float64List(_size + 1);
  double _totalSum = 0;

  /// The number of elements.
  int get size => _size;

  /// The sum of all elements, kept in O(1).
  double get totalSum => _totalSum;

  /// Adds [delta] to the element at [index].
  void update(int index, double delta) {
    assert(
      index >= 0 && index < _size,
      'Index $index out of range [0, $_size)',
    );
    _totalSum += delta;
    var i = index + 1;
    while (i <= _size) {
      _tree[i] += delta;
      i += i & -i;
    }
  }

  /// Replaces the element at [index], given its current value.
  void set(int index, double oldValue, double newValue) =>
      update(index, newValue - oldValue);

  /// The sum of the elements at `0..index` inclusive.
  double prefixSum(int index) {
    assert(
      index >= 0 && index < _size,
      'Index $index out of range [0, $_size)',
    );
    var sum = 0.0;
    var i = index + 1;
    while (i > 0) {
      sum += _tree[i];
      i -= i & -i;
    }
    return sum;
  }

  /// The sum of the elements at `left..right` inclusive.
  double rangeSum(int left, int right) {
    assert(left >= 0 && left <= right && right < _size);
    if (left == 0) return prefixSum(right);
    return prefixSum(right) - prefixSum(left - 1);
  }

  /// The index of the element containing [pixelOffset]: the largest
  /// index whose start (the sum of everything before it) is at most the
  /// offset. Returns -1 when the offset is beyond the total, 0 when it
  /// is negative. O(log n) by binary lifting.
  int findItemAtOffset(double pixelOffset) {
    if (_size == 0) return -1;
    if (pixelOffset < 0) return 0;
    if (pixelOffset >= _totalSum) return -1;
    var pos = 0;
    var remaining = pixelOffset;
    var bitMask = 1 << (_size.bitLength - 1);
    while (bitMask > 0) {
      final next = pos + bitMask;
      if (next <= _size && _tree[next] <= remaining) {
        pos = next;
        remaining -= _tree[next];
      }
      bitMask >>= 1;
    }
    return pos;
  }

  /// Resizes to [newSize], keeping the first `min(old, new)` values.
  void resize(int newSize) {
    if (newSize == _size) return;
    final old = [
      for (var i = 0; i < _size; i++) i == 0 ? prefixSum(0) : rangeSum(i, i),
    ];
    _size = newSize;
    _tree = Float64List(newSize + 1);
    _totalSum = 0;
    final limit = old.length < newSize ? old.length : newSize;
    _fill(old.sublist(0, limit));
  }

  void _fill(List<double> values) {
    var total = 0.0;
    for (var i = 0; i < values.length; i++) {
      _tree[i + 1] = values[i];
      total += values[i];
    }
    _totalSum = total;
    for (var i = 1; i <= _size; i++) {
      final parent = i + (i & -i);
      if (parent <= _size) _tree[parent] += _tree[i];
    }
  }
}
