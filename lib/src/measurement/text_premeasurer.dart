import 'package:flutter/widgets.dart';

import '../engine/model/item_type_config.dart';

/// Measures text with a [TextPainter] to produce content-aware height
/// estimates without building widgets. One painter is reused; call
/// [dispose] when done.
class TextPremeasurer({final TextDirection textDirection = TextDirection.ltr}) {
  late final TextPainter _painter = TextPainter(textDirection: textDirection);

  /// The height of [text] in [style] at [maxWidth], plus [padding].
  HeightEstimate measureText({
    required String text,
    required TextStyle style,
    required double maxWidth,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) => measureTextSpan(
    textSpan: TextSpan(text: text, style: style),
    maxWidth: maxWidth,
    padding: padding,
    maxLines: maxLines,
    strutStyle: strutStyle,
    confidence: 0.9,
  );

  /// The height of a rich [textSpan] at [maxWidth], plus [padding].
  HeightEstimate measureTextSpan({
    required TextSpan textSpan,
    required double maxWidth,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
    double confidence = 0.85,
  }) {
    final availableWidth = maxWidth - padding.horizontal;
    if (availableWidth <= 0) return (height: padding.vertical, confidence: 0.5);
    _painter
      ..text = textSpan
      ..maxLines = maxLines
      ..strutStyle = strutStyle
      ..layout(maxWidth: availableWidth);
    return (height: _painter.height + padding.vertical, confidence: confidence);
  }

  /// An [ItemTypeConfig.estimator] over the text [textExtractor] returns.
  HeightEstimate Function(T data, double availableWidth) createEstimator<T>({
    required String Function(T data) textExtractor,
    required TextStyle style,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) =>
      (data, availableWidth) => measureText(
        text: textExtractor(data),
        style: style,
        maxWidth: availableWidth,
        padding: padding,
        maxLines: maxLines,
        strutStyle: strutStyle,
      );

  /// An [ItemTypeConfig.estimator] over the span [spanBuilder] returns.
  HeightEstimate Function(T data, double availableWidth)
  createRichEstimator<T>({
    required TextSpan Function(T data) spanBuilder,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) =>
      (data, availableWidth) => measureTextSpan(
        textSpan: spanBuilder(data),
        maxWidth: availableWidth,
        padding: padding,
        maxLines: maxLines,
        strutStyle: strutStyle,
      );

  /// Releases the painter.
  void dispose() => _painter.dispose();
}
