import '../model/reader_item.dart';
import '../registry/item_registry.dart';
import '../scroll/scroll_compensator.dart';

/// Which edge of the loaded items new content belongs to.
enum LoadDirection() {
  /// Before the first item (older history in a chat).
  before,

  /// After the last item.
  after
}

/// The items intersecting the viewport, in data order.
class const VisibilityState({
  final int firstVisible = -1,
  final int lastVisible = -1,
  final int anchorIndex = 0,
  final double scrollOffset = 0,
}) {
  /// Whether anything is visible.
  bool get hasVisible => firstVisible >= 0;

  /// Whether [index] is within the visible range.
  bool contains(int index) => index >= firstVisible && index <= lastVisible;

  @override
  bool operator ==(Object other) =>
      other is VisibilityState &&
      other.firstVisible == firstVisible &&
      other.lastVisible == lastVisible &&
      other.anchorIndex == anchorIndex &&
      other.scrollOffset == scrollOffset;

  @override
  int get hashCode =>
      Object.hash(firstVisible, lastVisible, anchorIndex, scrollOffset);

  @override
  String toString() =>
      'VisibilityState($firstVisible..$lastVisible, anchor $anchorIndex)';
}

/// The outcome of a jump: where to scroll and how far off it may be.
class const JumpResult({
  required final double pixelOffset,
  final double estimatedError = 0,
});

/// The outcome of a measurement report.
class const MeasurementResult({required final double scrollCompensation});

/// The pure-Dart coordinator over an [ItemRegistry]: jumps, measurement
/// with model-offset compensation, visibility from a reported scroll
/// offset, and batch mutations. The widget layer lays out from the
/// registry directly and keeps its reference item fixed inside layout;
/// this facade serves engine-only users and the measurement scheduler.
class ReaderEngine<T>({required final ItemRegistry<T> registry}) {
  final ScrollCompensator _compensator = ScrollCompensator();
  double _viewportHeight = 0;
  double _scrollOffset = 0;
  VisibilityState _visibility = const VisibilityState();

  /// Called whenever the visible items change.
  void Function(VisibilityState state)? onVisibilityChanged;

  // ── Queries ──────────────────────────────────────────────────────────

  double get totalHeight => registry.totalHeight;
  int get itemCount => registry.itemCount;
  VisibilityState get visibility => _visibility;
  ReaderItem<T> itemAt(int index) => registry.itemAt(index);
  double get averageConfidence => registry.averageConfidence;

  // ── Viewport ─────────────────────────────────────────────────────────

  void setViewportHeight(double height) {
    _viewportHeight = height;
    _updateVisibility();
  }

  void reportScrollOffset(double offset) {
    _scrollOffset = offset;
    _updateVisibility();
  }

  // ── Navigation ───────────────────────────────────────────────────────

  /// The offset of [id] and the estimated error of the jump, or null.
  JumpResult? jumpToId(String id) {
    final loc = registry.locateById(id);
    if (loc == null) return null;
    return _jumpTo(loc.index, loc.offset);
  }

  JumpResult jumpToIndex(int index) =>
      _jumpTo(index, registry.offsetOfIndex(index));

  JumpResult _jumpTo(int index, double offset) {
    final error = registry.estimatedJumpError(
      _visibility.anchorIndex.clamp(0, itemCount - 1),
      index,
    );
    _scrollOffset = offset;
    _compensator.reset();
    _updateVisibility();
    return JumpResult(pixelOffset: offset, estimatedError: error);
  }

  // ── Measurement ──────────────────────────────────────────────────────

  MeasurementResult reportMeasuredHeight(int index, double height) {
    _compensator.reportHeightChange(
      index,
      registry.reportMeasuredHeight(index, height),
    );
    return MeasurementResult(scrollCompensation: _consume());
  }

  /// Reports several rendered heights; returns the total compensation.
  double reportMeasuredHeights(Map<int, double> measurements) {
    for (final MapEntry(:key, :value) in measurements.entries) {
      _compensator.reportHeightChange(
        key,
        registry.reportMeasuredHeight(key, value),
      );
    }
    return _consume();
  }

  /// Reports several content-aware estimates; returns the compensation.
  double reportEstimatedHeights(
    Map<int, double> estimates, {
    double confidence = 0.9,
  }) {
    for (final MapEntry(:key, :value) in estimates.entries) {
      _compensator.reportHeightChange(
        key,
        registry.reportEstimatedHeight(key, value, confidence: confidence),
      );
    }
    return _consume();
  }

  // ── Dynamic content ──────────────────────────────────────────────────

  double insertItem(int index, ReaderItem<T> item, {double? estimatedHeight}) {
    registry.insert(index, item, estimatedHeight: estimatedHeight);
    _compensator.reportHeightChange(index, registry.heightAt(index));
    return _consume();
  }

  double removeItem(int index) {
    final removed = registry.heightAt(index);
    registry.removeAt(index);
    _compensator.reportHeightChange(index, -removed);
    return _consume();
  }

  /// Inserts [items] at [index] as one change; returns the compensation.
  double insertItems(
    int index,
    List<ReaderItem<T>> items, {
    List<double?>? estimatedHeights,
  }) {
    if (items.isEmpty) return 0;
    registry.insertAll(index, items, estimatedHeights: estimatedHeights);
    var inserted = 0.0;
    for (var i = 0; i < items.length; i++) {
      inserted += registry.heightAt(index + i);
    }
    _compensator.reportHeightChange(index, inserted);
    return _consume();
  }

  /// Removes [count] items from [startIndex]; returns the compensation.
  double removeItems(int startIndex, int count) {
    if (count <= 0) return 0;
    var removed = 0.0;
    for (var i = startIndex; i < startIndex + count; i++) {
      removed += registry.heightAt(i);
    }
    registry.removeRange(startIndex, count);
    _compensator.reportHeightChange(startIndex, -removed);
    return _consume();
  }

  // ── Diagnostics ──────────────────────────────────────────────────────

  /// Up to [count] items below [threshold] confidence, least first.
  List<int> nextItemsToMeasure({int count = 20, double threshold = 0.5}) =>
      registry.lowConfidenceItems(threshold: threshold, limit: count);

  // ── Width change ─────────────────────────────────────────────────────

  /// Re-estimates heights for [newWidth]; returns the compensation that
  /// keeps the anchor item's offset.
  double onWidthChanged(double newWidth) {
    if (itemCount == 0) {
      registry.onWidthChanged(newWidth);
      return 0;
    }
    final anchor = _visibility.anchorIndex.clamp(0, itemCount - 1);
    final oldAnchorOffset = registry.offsetOfIndex(anchor);
    final (first, last) = _viewportHeight > 0
        ? registry.visibleRange(_scrollOffset, _viewportHeight)
        : (-1, -1);
    registry.onWidthChanged(
      newWidth,
      viewportRange: first >= 0 ? (first, last) : null,
    );
    final compensation = registry.offsetOfIndex(anchor) - oldAnchorOffset;
    _scrollOffset += compensation;
    _updateVisibility();
    return compensation;
  }

  // ── Private ──────────────────────────────────────────────────────────

  double _consume() {
    final compensation = _compensator.consumeCompensation();
    if (compensation != 0) _scrollOffset += compensation;
    _updateVisibility();
    return compensation;
  }

  void _updateVisibility() {
    if (_viewportHeight <= 0) return;
    final (first, last) = registry.visibleRange(_scrollOffset, _viewportHeight);
    final anchor = first >= 0 ? first : 0;
    _compensator.setAnchor(anchor);
    final next = VisibilityState(
      firstVisible: first,
      lastVisible: last,
      anchorIndex: anchor,
      scrollOffset: _scrollOffset,
    );
    if (next == _visibility) return;
    _visibility = next;
    onVisibilityChanged?.call(next);
  }
}
