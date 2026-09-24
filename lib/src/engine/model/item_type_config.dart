/// How an item type's height responds to a viewport width change.
enum WidthSensitivity() {
  /// The height does not depend on the width (dividers, fixed rows).
  /// On resize: nothing to do.
  invariant,

  /// The height is a function of the width (an image with a known
  /// aspect ratio). On resize: recomputed arithmetically.
  proportional,

  /// The height depends on text layout (paragraphs, chat bubbles).
  /// On resize: re-estimated through the estimator, then re-measured.
  dependent
}

/// A height estimate with its confidence in `[0, 1]`.
typedef HeightEstimate = ({double height, double confidence});

/// Configuration for one item type: a default height, how it reacts to
/// width changes and, optionally, an estimator that reads the payload.
class const ItemTypeConfig<T>({
  required final String typeName,

  /// The height assumed before anything better is known.
  required final double defaultHeight,

  /// Confidence in [defaultHeight], `0.0` to `1.0`.
  final double defaultConfidence = 0.2,
  final WidthSensitivity widthSensitivity = WidthSensitivity.dependent,

  /// A content-aware estimate from the payload and the available width.
  /// When set, it replaces [defaultHeight] at build time and on resize.
  final HeightEstimate Function(T data, double availableWidth)? estimator,

  /// For [WidthSensitivity.proportional] types: the exact height at a
  /// width (for example `width / aspectRatio`).
  final double Function(T data, double availableWidth)? proportionalHeightFn,
});
