import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  const verses = [
    'In the beginning',
    'faith, hope and love',
    'the greatest of these is love',
    'nothing here',
    'Love never fails',
  ];

  ReaderController<String> readerOf() => ReaderController<String>(
    items: verses,
    idOf: (v) => v,
    typeKeyOf: (_) => 'verse',
    typeConfigs: const {
      'verse': ItemTypeConfig<String>(typeName: 'verse', defaultHeight: 40),
    },
    initialWidth: 400,
  );

  ReaderSearchController<String> searchOf(ReaderController<String> reader) =>
      ReaderSearchController<String>(
        reader: reader,
        textExtractors: {'verse': (data) => data},
        debounceDuration: Duration.zero,
      );

  test('finds every occurrence, case-insensitively, in item order', () {
    final reader = readerOf();
    final search = searchOf(reader);
    search.search('love');
    expect(search.isActive, isTrue);
    expect(search.matchCount, 3);
    expect([for (final m in search.matches) m.itemIndex], [1, 2, 4]);
    expect(search.matches.first.matchedText, 'love');
    expect(search.matches.last.matchedText, 'Love');
    expect(search.currentMatchIndex, 0);
    expect(search.isItemMatch(2), isTrue);
    expect(search.isItemMatch(3), isFalse);
    expect(search.isCurrentMatch(1), isTrue);
    expect(search.matchesForItem(4).single.matchStart, 0);
  });

  test('several matches inside one item', () {
    final reader = readerOf();
    final search = searchOf(reader);
    search.search('e');
    expect(search.matchesForItem(2).length, 6);
    expect(search.matchesForItem(1).length, 2);
  });

  test('navigation wraps both ways', () {
    final reader = readerOf();
    final search = searchOf(reader)..search('love');
    search.nextMatch();
    expect(search.currentMatchIndex, 1);
    search.nextMatch();
    search.nextMatch();
    expect(search.currentMatchIndex, 0);
    search.previousMatch();
    expect(search.currentMatchIndex, 2);
    search.jumpToMatch(1);
    expect(search.currentMatchIndex, 1);
    search.jumpToMatch(9);
    expect(search.currentMatchIndex, 1);
  });

  test('no results, clear, and empty queries', () {
    final reader = readerOf();
    final search = searchOf(reader);
    var notified = 0;
    search.addListener(() => notified++);
    search.search('zzz');
    expect(search.hasMatches, isFalse);
    expect(search.currentMatch, isNull);
    expect(search.isActive, isTrue);
    search.search('   ');
    expect(search.isActive, isFalse);
    search.search('love');
    search.clear();
    expect(search.matches, isEmpty);
    expect(notified, 4);
  });

  test('a throwing extractor skips the item', () {
    final reader = readerOf();
    final search = ReaderSearchController<String>(
      reader: reader,
      textExtractors: {
        'verse': (data) =>
            data.startsWith('nothing') ? throw StateError('x') : data,
      },
      debounceDuration: Duration.zero,
    );
    search.search('n');
    expect([for (final m in search.matches) m.itemIndex], isNot(contains(3)));
  });

  testWidgets('a debounced query runs once and jumps to the first match', (
    tester,
  ) async {
    final controller = controllerOf(items(300));
    final scroll = ScrollController();
    final search = ReaderSearchController<Item>(
      reader: controller,
      textExtractors: {'item': (item) => item.id},
      alignment: 0,
    );
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    search
      ..search('item_20')
      ..search('item_250');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(search.matchCount, 1);
    expect(topOfScreen(tester), ('item_250', 0.0));
    search.dispose();
    controller.dispose();
    scroll.dispose();
  });

  test('buildHighlightedSpan styles matches and the current one', () {
    const base = TextStyle(fontSize: 12);
    const hi = TextStyle(backgroundColor: Color(0x22000000));
    const cur = TextStyle(backgroundColor: Color(0x44000000));
    final matches = [
      const SearchMatch(
        itemIndex: 0,
        itemId: 'a',
        text: 'ab ab',
        matchStart: 0,
        matchEnd: 2,
      ),
      const SearchMatch(
        itemIndex: 0,
        itemId: 'a',
        text: 'ab ab',
        matchStart: 3,
        matchEnd: 5,
      ),
    ];
    final span = buildHighlightedSpan(
      text: 'ab ab',
      matches: matches,
      currentMatch: matches[1],
      style: base,
      highlightStyle: hi,
      currentHighlightStyle: cur,
    );
    final children = span.children!.cast<TextSpan>();
    expect([for (final c in children) c.text], ['ab', ' ', 'ab']);
    expect(children[0].style, hi);
    expect(children[2].style, cur);
    expect(span.style, base);
    expect(
      buildHighlightedSpan(
        text: 'x',
        matches: const [],
        highlightStyle: hi,
        currentHighlightStyle: cur,
      ).text,
      'x',
    );
  });
}
