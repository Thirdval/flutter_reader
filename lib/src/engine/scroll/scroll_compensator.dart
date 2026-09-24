/// Accumulates the scroll offset compensation that keeps an anchor item
/// visually still when heights change above it.
///
/// A change at an index before the anchor shifts everything after it;
/// the compensation is the sum of those deltas. Changes at or after the
/// anchor need none. The pure-Dart [ReaderEngine] uses this for model
/// offsets; the widget layer keeps its reference child fixed inside
/// layout instead and never consults it.
class ScrollCompensator() {
  static const _epsilon = 1e-10;

  int _anchorIndex = 0;
  double _pending = 0;

  /// The index of the anchor item, normally the first visible one.
  int get anchorIndex => _anchorIndex;

  /// Whether a compensation is waiting to be consumed.
  bool get hasPendingCompensation => _pending.abs() >= _epsilon;

  /// Sets the anchor; call whenever the visible range changes.
  void setAnchor(int index) => _anchorIndex = index;

  /// Records a height change of [delta] at [itemIndex].
  void reportHeightChange(int itemIndex, double delta) {
    if (delta.abs() < _epsilon) return;
    if (itemIndex < _anchorIndex) _pending += delta;
  }

  /// Records several height changes at once.
  void reportHeightChanges(Map<int, double> deltas) {
    for (final MapEntry(:key, :value) in deltas.entries) {
      reportHeightChange(key, value);
    }
  }

  /// Returns the pending compensation and resets it. Positive means the
  /// content above grew, so the offset must grow by as much.
  double consumeCompensation() {
    final value = _pending;
    _pending = 0;
    return value;
  }

  /// Clears the anchor and the pending compensation.
  void reset() {
    _anchorIndex = 0;
    _pending = 0;
  }
}
