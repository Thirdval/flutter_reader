import '../engine/registry/item_registry.dart';

/// What the sliver needs from the items, in *layout* order: index 0 is
/// the first child the sliver lays out. In forward mode that is the
/// first data item; in reverse mode it is the last.
abstract interface class ReaderLayoutModel() {
  int get itemCount;
  double get totalExtent;

  /// The current extent (measured or estimated) of the item at [rawIndex].
  double extentAt(int rawIndex);

  /// The estimated layout offset of [rawIndex]: the sum of every extent
  /// before it.
  double offsetAt(int rawIndex);

  /// The item containing [rawOffset], clamped to the first and last item;
  /// -1 when empty.
  int indexAtOffset(double rawOffset);

  String idAt(int rawIndex);
  int? indexOfId(String id);

  int dataIndexOf(int rawIndex);
  int rawIndexOf(int dataIndex);

  /// Records a rendered extent for [rawIndex].
  void reportExtent(int rawIndex, double extent);
}

/// Layout order equals data order.
class ForwardLayoutModel<T>(final ItemRegistry<T> _registry)
    implements ReaderLayoutModel {
  @override
  int get itemCount => _registry.itemCount;

  @override
  double get totalExtent => _registry.totalHeight;

  @override
  double extentAt(int rawIndex) => _registry.heightAt(rawIndex);

  @override
  double offsetAt(int rawIndex) => _registry.offsetOfIndex(rawIndex);

  @override
  int indexAtOffset(double rawOffset) {
    final count = _registry.itemCount;
    if (count == 0) return -1;
    if (rawOffset <= 0) return 0;
    final index = _registry.itemIndexAtOffset(rawOffset);
    return index < 0 ? count - 1 : index;
  }

  @override
  String idAt(int rawIndex) => _registry.idAt(rawIndex);

  @override
  int? indexOfId(String id) => _registry.indexOfId(id);

  @override
  int dataIndexOf(int rawIndex) => rawIndex;

  @override
  int rawIndexOf(int dataIndex) => dataIndex;

  @override
  void reportExtent(int rawIndex, double extent) =>
      _registry.reportMeasuredHeight(rawIndex, extent);
}

/// Layout order is the reverse of data order: raw index 0 is the last
/// data item, and raw offsets count from the end of the data.
class ReverseLayoutModel<T>(final ItemRegistry<T> _registry)
    implements ReaderLayoutModel {
  static const _epsilon = 1e-6;

  @override
  int get itemCount => _registry.itemCount;

  @override
  double get totalExtent => _registry.totalHeight;

  int _flip(int index) => _registry.itemCount - 1 - index;

  @override
  double extentAt(int rawIndex) => _registry.heightAt(_flip(rawIndex));

  @override
  double offsetAt(int rawIndex) {
    final data = _flip(rawIndex);
    return _registry.totalHeight -
        _registry.offsetOfIndex(data) -
        _registry.heightAt(data);
  }

  @override
  int indexAtOffset(double rawOffset) {
    final count = _registry.itemCount;
    if (count == 0) return -1;
    if (rawOffset <= 0) return 0;
    final total = _registry.totalHeight;
    if (rawOffset >= total) return count - 1;
    // A raw offset o lies in the data item containing (total − o) from
    // the end of that item, hence the nudge below the boundary.
    final data = _registry.itemIndexAtOffset(
      (total - rawOffset - _epsilon).clamp(0, total),
    );
    return data < 0 ? count - 1 : _flip(data);
  }

  @override
  String idAt(int rawIndex) => _registry.idAt(_flip(rawIndex));

  @override
  int? indexOfId(String id) {
    final data = _registry.indexOfId(id);
    return data == null ? null : _flip(data);
  }

  @override
  int dataIndexOf(int rawIndex) => _flip(rawIndex);

  @override
  int rawIndexOf(int dataIndex) => _flip(dataIndex);

  @override
  void reportExtent(int rawIndex, double extent) =>
      _registry.reportMeasuredHeight(_flip(rawIndex), extent);
}
