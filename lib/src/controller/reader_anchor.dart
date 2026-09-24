/// An item the list keeps pinned: its leading edge stays at [alignment]
/// (a fraction of the viewport from the viewport's leading edge) while
/// items change around it. Setting an anchor places it once; while it
/// stays set the item is the list's reference child. An anchor naming an
/// item that is not loaded yet is placed as soon as it appears.
class const ReaderAnchor({
  required final String id,
  final double alignment = 0,
}) {
  this
    : assert(alignment >= 0 && alignment <= 1, 'alignment must be in [0, 1]');

  @override
  bool operator ==(Object other) =>
      other is ReaderAnchor && other.id == id && other.alignment == alignment;

  @override
  int get hashCode => Object.hash(id, alignment);

  @override
  String toString() => 'ReaderAnchor($id @ $alignment)';
}

/// A one-shot request to place an item, fulfilled inside the next layout.
/// The [serial] distinguishes repeated requests for the same item.
class const ReaderJump({
  required final String id,
  required final int serial,
  final double alignment = 0,

  /// Align the item's trailing edge instead of its leading edge.
  final bool trailingEdge = false,
}) {
  @override
  bool operator ==(Object other) =>
      other is ReaderJump && other.serial == serial;

  @override
  int get hashCode => serial;
}

/// What a layout pass saw, in layout (raw) indices.
class const ReaderLayoutReport({
  required final int firstVisibleRaw,
  required final int lastVisibleRaw,

  /// Raw index 0 is attached (inside the cache window).
  required final bool leadingEdgeReached,

  /// The last raw index is attached (inside the cache window).
  required final bool trailingEdgeReached,

  /// Layout offset minus model offset of the first attached child.
  required final double drift,

  /// The serial of the last [ReaderJump] this sliver fulfilled, or -1.
  final int fulfilledJumpSerial = -1,

  /// The anchor that settled at its alignment in this pass, if any.
  final String? placedAnchorId,

  /// Where the first visible child starts, relative to the sliver's
  /// scroll offset (negative when it starts before the viewport).
  final double firstVisibleOffset = 0,

  /// The sliver's paint area in this pass.
  final double paintExtent = 0,
});
