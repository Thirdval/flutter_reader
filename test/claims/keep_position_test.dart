/// README claim: what is on screen stays where it is while items are
/// added, removed or re-measured around it, in both directions.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('reverse: loading older pages moves nothing', (tester) async {
    final controller = controllerOf(items(100), hasMoreBefore: true);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    await tester.drag(find.byType(ReaderViewFinder), const Offset(0, 500));
    await tester.pumpAndSettle();
    final before = onScreen(tester);
    final offset = pixels(tester);
    for (var page = 0; page < 10; page++) {
      controller.setItems([
        ...items(20, from: 1000 + page * 20),
        ...controller.items,
      ]);
      await tester.pump();
      await tester.pump();
    }
    expect(onScreen(tester), before);
    expect(pixels(tester), offset);
    expect(controller.itemCount, 300);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('reverse: a new message while scrolled up moves nothing', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    await tester.drag(find.byType(ReaderViewFinder), const Offset(0, 500));
    await tester.pumpAndSettle();
    final before = onScreen(tester);
    controller.setItems([...controller.items, const Item(100)]);
    await tester.pump();
    await tester.pump();
    expect(onScreen(tester), before);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('reverse: at the end a new message pushes in', (tester) async {
    final controller = controllerOf(items(100), atEndThreshold: 48);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(bottomOfScreen(tester), ('item_99', 550.0));
    controller.setItems([...controller.items, const Item(100)]);
    await tester.pump();
    await tester.pump();
    expect(bottomOfScreen(tester), ('item_100', 550.0));
    expect(topOf(tester, 'item_99'), 500.0);
    expect(pixels(tester), 0.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('forward: prepending items with real heights moves nothing', (
    tester,
  ) async {
    double heightOf(Item item) => item.n.isEven ? 30 : 90; // estimates say 50
    final controller = controllerOf(items(100), hasMoreBefore: true);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, heightOf: heightOf));
    await tester.pump();
    await tester.drag(find.byType(ReaderViewFinder), const Offset(0, -700));
    await tester.pumpAndSettle();
    final before = onScreen(tester);
    controller.prependItems(items(10, from: 100));
    await tester.pump();
    await tester.pump();
    expect(onScreen(tester), before);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets(
    'an edit above the viewport that changes a height moves nothing',
    (tester) async {
      var tall = <int>{};
      double heightOf(Item item) => tall.contains(item.n) ? 150 : 50;
      final controller = controllerOf(items(100));
      final scroll = ScrollController();
      await tester.pumpWidget(host(controller, scroll, heightOf: heightOf));
      await tester.pump();
      await tester.drag(find.byType(ReaderViewFinder), const Offset(0, -1000));
      await tester.pumpAndSettle();
      final before = onScreen(tester);
      tall = {18}; // just above the viewport (items 20.. are visible)
      controller.updateItem(18, const Item(18));
      await tester.pump();
      await tester.pump();
      expect(onScreen(tester), before);
      controller.dispose();
      scroll.dispose();
    },
  );

  testWidgets('removing the top visible item keeps the next one in place', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    await tester.drag(find.byType(ReaderViewFinder), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final (topId, _) = topOfScreen(tester);
    final topIndex = int.parse(topId.substring(5));
    final nextTop = topOf(tester, 'item_${topIndex + 1}')!;
    controller.setItems([
      for (final item in controller.items)
        if (item.n != topIndex) item,
    ]);
    await tester.pump();
    await tester.pump();
    expect(topOf(tester, 'item_${topIndex + 1}'), nextTop);
    expect(find.text(topId), findsNothing);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a reorder rebuilds without moving what is visible', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    await tester.drag(find.byType(ReaderViewFinder), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final before = onScreen(tester);
    final list = controller.items.toList();
    // Swap two items far below the viewport.
    final tmp = list[80];
    list[80] = list[81];
    list[81] = tmp;
    controller.setItems(list);
    await tester.pump();
    await tester.pump();
    expect(onScreen(tester), before);
    controller.dispose();
    scroll.dispose();
  });
}

/// The scrollable inside the view, for gestures.
typedef ReaderViewFinder = Scrollable;
