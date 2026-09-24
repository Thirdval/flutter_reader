import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/reader_controller.dart';

/// One match: the item (data index and id), the text searched and the
/// match's character range in it.
class const SearchMatch({
  required final int itemIndex,
  required final String itemId,
  required final String text,
  required final int matchStart,
  required final int matchEnd,
}) {
  String get matchedText => text.substring(matchStart, matchEnd);
}

/// Case-insensitive text search over a [ReaderController]'s loaded
/// items, with debounced queries and next / previous navigation that
/// jumps to the match. Display strings are the host's: this exposes
/// counts and indices only.
class ReaderSearchController<T>({
  required final ReaderController<T> reader,

  /// The searchable text per type key; other types are skipped.
  required final Map<String, String Function(T data)> textExtractors,

  /// The wait after the last keystroke; [Duration.zero] searches at once.
  final Duration debounceDuration = const Duration(milliseconds: 300),

  /// Where a match lands in the viewport; see [ReaderController.jumpToId].
  final double alignment = 0.3,
}) extends ChangeNotifier {
  String _query = '';
  List<SearchMatch> _matches = const [];
  Set<int> _matchIndices = const {};
  int _currentIndex = -1;
  Timer? _debounce;

  String get query => _query;
  List<SearchMatch> get matches => _matches;
  int get currentMatchIndex => _currentIndex;
  SearchMatch? get currentMatch =>
      _currentIndex >= 0 && _currentIndex < _matches.length
      ? _matches[_currentIndex]
      : null;
  int get matchCount => _matches.length;
  bool get hasMatches => _matches.isNotEmpty;
  bool get isActive => _query.isNotEmpty;

  bool isItemMatch(int index) => _matchIndices.contains(index);

  bool isCurrentMatch(int index) => currentMatch?.itemIndex == index;

  List<SearchMatch> matchesForItem(int index) => isItemMatch(index)
      ? [
          for (final m in _matches)
            if (m.itemIndex == index) m,
        ]
      : const [];

  /// Searches for [query] (trimmed); an empty query clears.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }
    _query = trimmed;
    _debounce?.cancel();
    if (debounceDuration == Duration.zero) {
      _execute(trimmed);
    } else {
      _debounce = Timer(debounceDuration, () => _execute(trimmed));
    }
  }

  void clear() {
    _debounce?.cancel();
    _query = '';
    _matches = const [];
    _matchIndices = const {};
    _currentIndex = -1;
    notifyListeners();
  }

  /// Moves to the next match, wrapping around.
  void nextMatch() {
    if (_matches.isEmpty) return;
    _select((_currentIndex + 1) % _matches.length);
  }

  /// Moves to the previous match, wrapping around.
  void previousMatch() {
    if (_matches.isEmpty) return;
    _select((_currentIndex - 1 + _matches.length) % _matches.length);
  }

  void jumpToMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _matches.length) return;
    _select(matchIndex);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _select(int index) {
    _currentIndex = index;
    if (currentMatch case final match?) {
      reader.jumpToId(match.itemId, alignment: alignment);
    }
    notifyListeners();
  }

  void _execute(String query) {
    _matches = _findMatches(query);
    _matchIndices = {for (final m in _matches) m.itemIndex};
    if (_matches.isNotEmpty) {
      _select(0);
    } else {
      _currentIndex = -1;
      notifyListeners();
    }
  }

  List<SearchMatch> _findMatches(String query) {
    final lowerQuery = query.toLowerCase();
    final results = <SearchMatch>[];
    for (var i = 0; i < reader.itemCount; i++) {
      final item = reader.registry.itemAt(i);
      final extractor = textExtractors[item.typeKey];
      if (extractor == null) continue;
      final String text;
      try {
        text = extractor(item.data);
      } on Object {
        assert(() {
          debugPrint(
            'ReaderSearchController: the extractor for "${item.typeKey}" '
            'threw on item "${item.id}"; skipped.',
          );
          return true;
        }());
        continue;
      }
      final lowerText = text.toLowerCase();
      var from = 0;
      while (true) {
        final at = lowerText.indexOf(lowerQuery, from);
        if (at < 0) break;
        results.add(
          SearchMatch(
            itemIndex: i,
            itemId: item.id,
            text: text,
            matchStart: at,
            matchEnd: at + query.length,
          ),
        );
        from = at + 1;
      }
    }
    return results;
  }
}
