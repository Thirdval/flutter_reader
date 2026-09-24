part of 'reader_controller.dart';

/// Animated navigation: an animation towards the model's estimate, then
/// an exact placement.
extension ReaderControllerNavigation<T> on ReaderController<T> {
  /// Animates towards the item, then places it exactly.
  Future<void> animateToId(
    String id, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final position = _position;
    final data = _registry.indexOfId(id);
    if (position == null || data == null) return;
    final raw = _model.rawIndexOf(data);
    final estimate =
        _model.offsetAt(raw) +
        (_report?.drift ?? 0) -
        alignment * position.viewportDimension;
    await position.animateTo(
      estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: duration,
      curve: curve,
    );
    jumpToId(id, alignment: alignment);
  }

  Future<void> animateToIndex(
    int index, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) => animateToId(
    _registry.idAt(index),
    alignment: alignment,
    duration: duration,
    curve: curve,
  );

  /// Animates to the end of the list.
  Future<void> animateToEnd({
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final position = _position;
    if (position == null) return;
    await position.animateTo(
      _reverse ? position.minScrollExtent : position.maxScrollExtent,
      duration: duration,
      curve: curve,
    );
    scrollToEnd();
  }
}
