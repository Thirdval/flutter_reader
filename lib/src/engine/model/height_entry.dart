/// Accuracy tier of a height value.
enum HeightTier() {
  /// A type-based constant. Lowest accuracy.
  estimate,

  /// A content-aware estimate (a text measurement, an aspect ratio).
  premeasured,

  /// The rendered extent. Ground truth.
  measured
}

/// One item's height state.
class HeightEntry({
  required var double height,
  var HeightTier tier = HeightTier.estimate,
  var double confidence = 0.2,

  /// The viewport width the height was determined at.
  var double? measuredAtWidth,
}) {
  HeightEntry copyWith({
    double? height,
    HeightTier? tier,
    double? confidence,
    double? measuredAtWidth,
  }) => HeightEntry(
    height: height ?? this.height,
    tier: tier ?? this.tier,
    confidence: confidence ?? this.confidence,
    measuredAtWidth: measuredAtWidth ?? this.measuredAtWidth,
  );
}
