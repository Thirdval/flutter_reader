import 'package:flutter/painting.dart';

import 'reader_search_controller.dart';

/// A [TextSpan] over [text] with [matches] in [highlightStyle] and the
/// [currentMatch] in [currentHighlightStyle]. The styles are the host's;
/// nothing here picks a colour.
TextSpan buildHighlightedSpan({
  required String text,
  required List<SearchMatch> matches,
  required TextStyle highlightStyle,
  required TextStyle currentHighlightStyle,
  SearchMatch? currentMatch,
  TextStyle? style,
}) {
  if (matches.isEmpty) return TextSpan(text: text, style: style);
  final sorted = [...matches]..sort((a, b) => a.matchStart - b.matchStart);
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in sorted) {
    if (match.matchStart < cursor) continue; // overlapping match
    if (match.matchStart > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.matchStart)));
    }
    final isCurrent =
        currentMatch != null &&
        match.itemIndex == currentMatch.itemIndex &&
        match.matchStart == currentMatch.matchStart &&
        match.matchEnd == currentMatch.matchEnd;
    spans.add(
      TextSpan(
        text: text.substring(match.matchStart, match.matchEnd),
        style: isCurrent ? currentHighlightStyle : highlightStyle,
      ),
    );
    cursor = match.matchEnd;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return TextSpan(style: style, children: spans);
}
