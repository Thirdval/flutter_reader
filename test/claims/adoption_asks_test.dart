/// Scenarios the Tendvine adoption asked to see proven on the package
/// side: the anchor-placed signal, an anchor on the newest message, flags
/// travelling with setItems, an unknown initial width, moves near the
/// end and of the reference child, deleting the reference, ten pages of
/// heterogeneous heights, a keyboard-sized viewport change, PageStorage
/// across rooms, semantics after diffs, and the live widget count.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Chat-like heights: dividers, bubbles, images and polls.
double chatHeightOf(Item item) => switch (item.n % 10) {
  0 => 40,
  7 => 240 + (item.n % 4) * 20,
  8 => 200,
  _ => 60 + (item.n * 13) % 61,
};

void main() {
  testWidgets('onAnchorPlaced fires once, at once or when the item lands', (
    tester,
  ) async {
    final placed = <String>[];
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_50', alignment: 0.7),
        onAnchorPlaced: placed.add,
      ),
    );
    await tester.pump();
    expect(placed, ['item_50']);
    scroll.jumpTo(pixels(tester) + 200);
    await tester.pump();
    await tester.pump();
    expect(placed, ['item_50'], reason: 'no repeat on scroll');
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_500', alignment: 0.7),
        onAnchorPlaced: placed.add,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(placed, ['item_50'], reason: 'item_500 is not loaded yet');
    for (var page = 1; page <= 5; page++) {
      controller.setItems([
        ...controller.items,
        ...items(100, from: page * 100),
      ]);
      await tester.pump();
      await tester.pump();
    }
    expect(placed, ['item_50', 'item_500']);
    expect(topOf(tester, 'item_500'), 130.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('an anchor on the newest message means the end', (tester) async {
    final controller = controllerOf(items(100), atEndThreshold: 48);
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_99', alignment: 0.7),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(topOf(tester, 'item_99'), 550.0, reason: 'no blank space below');
    expect(pixels(tester), 0.0);
    expect(controller.isAtEnd, isTrue);
    controller.setItems([...controller.items, const Item(100)]);
    await tester.pump();
    expect(topOf(tester, 'item_100'), 550.0, reason: 'a new message pushes in');
    expect(pixels(tester), 0.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('setItems carries the edge flags', (tester) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(items(5), onEdgeReached: fired.add);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(fired, isEmpty);
    controller.setItems(items(5), hasMoreBefore: true);
    await tester.pump();
    await tester.pump();
    expect(fired, [LoadDirection.before]);
    controller.setItems([
      ...items(3, from: 100),
      ...items(5),
    ], hasMoreBefore: false);
    await tester.pump();
    await tester.pump();
    expect(fired.length, 1);
    expect(controller.hasMoreBefore, isFalse);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('an unknown initial width is set by the first layout', (
    tester,
  ) async {
    var estimatorWidths = <double>[];
    final controller = ReaderController<Item>(
      items: items(20),
      idOf: (i) => i.id,
      typeKeyOf: (_) => 'text',
      typeConfigs: {
        'text': ItemTypeConfig<Item>(
          typeName: 'text',
          defaultHeight: 50,
          estimator: (item, width) {
            estimatorWidths.add(width);
            return (height: width > 0 ? 50 : 10, confidence: 0.8);
          },
        ),
      },
    );
    expect(controller.registry.currentWidth, 0);
    expect(controller.registry.heightAt(0), 10);
    final scroll = ScrollController();
    estimatorWidths = [];
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    expect(controller.registry.currentWidth, 800);
    expect(estimatorWidths, everyElement(800));
    expect(controller.registry.heightAt(19), 50);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets(
    'a move near the end: at the end it shows, scrolled up nothing moves',
    (tester) async {
      final controller = controllerOf(items(100), atEndThreshold: 48);
      final scroll = ScrollController();
      await tester.pumpWidget(
        host(controller, scroll, reverse: true, heightOf: chatHeightOf),
      );
      await tester.pump();
      var list = controller.items.toList();
      var tmp = list[98];
      list[98] = list[99];
      list[99] = tmp;
      controller.setItems(list);
      await tester.pump();
      expect(
        rows(tester).last.$1,
        'item_98',
        reason: 'the swap is visible at the end',
      );
      expect(rows(tester).last.$2 + rows(tester).last.$3, 600.0);
      expect(pixels(tester), 0.0);
      scroll.jumpTo(1500);
      await tester.pump();
      final before = onScreen(tester);
      list = controller.items.toList();
      tmp = list[98];
      list[98] = list[99];
      list[99] = tmp;
      controller.setItems(list);
      await tester.pump();
      expect(onScreen(tester), before);
      controller.dispose();
      scroll.dispose();
    },
  );

  testWidgets('a move of the reference child keeps it in place', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, heightOf: chatHeightOf),
    );
    await tester.pump();
    scroll.jumpTo(1500);
    await tester.pump();
    final (refId, refTop, _) = rows(tester)
        .last; // the reference: nearest the origin
    final refIndex = controller.indexOfId(refId)!;
    final list = controller.items.toList();
    final tmp = list[refIndex];
    list[refIndex] = list[refIndex + 1];
    list[refIndex + 1] = tmp;
    controller.setItems(list);
    await tester.pump();
    expect(topOf(tester, refId), refTop);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('deleting the reference child while scrolled up', (tester) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, heightOf: chatHeightOf),
    );
    await tester.pump();
    scroll.jumpTo(1500);
    await tester.pump();
    final r = rows(tester);
    final (refId, _, _) = r.last;
    final (aboveId, aboveTop, _) = r[r.length - 2];
    controller.setItems([
      for (final i in controller.items)
        if (i.id != refId) i,
    ]);
    await tester.pump();
    expect(find.text(refId), findsNothing);
    expect(
      topOf(tester, aboveId),
      aboveTop,
      reason: 'the rest of the screen holds',
    );
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('ten heterogeneous pages land without a visible shift', (
    tester,
  ) async {
    for (final mode in ['scrolled up', 'anchored', 'at the top']) {
      final controller = controllerOf(
        items(50, from: 1000),
        hasMoreBefore: true,
      );
      final scroll = ScrollController();
      final anchor = mode == 'anchored'
          ? const ReaderAnchor(id: 'item_1020', alignment: 0.7)
          : null;
      await tester.pumpWidget(
        host(
          controller,
          scroll,
          reverse: true,
          anchor: anchor,
          heightOf: chatHeightOf,
          trailingSlivers: const [
            SliverToBoxAdapter(
              child: SizedBox(height: 48, child: Text('loader')),
            ),
          ],
        ),
      );
      await tester.pump();
      if (mode == 'scrolled up') scroll.jumpTo(900);
      if (mode == 'at the top') scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      final before = [
        for (final (id, top, _) in rows(tester))
          if (id != 'loader') (id, top),
      ];
      expect(before, isNotEmpty);
      for (var page = 1; page <= 10; page++) {
        controller.setItems([
          ...items(50, from: 1000 - page * 50),
          ...controller.items,
        ]);
        await tester.pump();
        await tester.pump();
      }
      final after = {for (final (id, top, _) in rows(tester)) id: top};
      for (final (id, top) in before) {
        expect(after[id], top, reason: '$mode: $id moved');
      }
      expect(controller.itemCount, 550);
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets(
    'a keyboard-sized viewport change keeps the bottom or the reference',
    (tester) async {
      final controller = controllerOf(items(100), atEndThreshold: 48);
      final scroll = ScrollController();
      await tester.pumpWidget(
        host(controller, scroll, reverse: true, heightOf: chatHeightOf),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(
          controller,
          scroll,
          reverse: true,
          heightOf: chatHeightOf,
          height: 360,
        ),
      );
      await tester.pump();
      final last = rows(tester).last;
      expect(last.$1, 'item_99');
      expect(last.$2 + last.$3, 360.0, reason: 'still at the end');
      expect(controller.isAtEnd, isTrue);
      await tester.pumpWidget(
        host(controller, scroll, reverse: true, heightOf: chatHeightOf),
      );
      await tester.pump();
      expect(rows(tester).last.$2 + rows(tester).last.$3, 600.0);
      scroll.jumpTo(1500);
      await tester.pump();
      final ref = rows(tester).last;
      await tester.pumpWidget(
        host(
          controller,
          scroll,
          reverse: true,
          heightOf: chatHeightOf,
          height: 360,
        ),
      );
      await tester.pump();
      expect(
        topOf(tester, ref.$1),
        ref.$2 - 240,
        reason: 'the reference keeps its offset from the bottom',
      );
      await tester.pumpWidget(
        host(controller, scroll, reverse: true, heightOf: chatHeightOf),
      );
      await tester.pump();
      expect(topOf(tester, ref.$1), ref.$2);
      controller.dispose();
      scroll.dispose();
    },
  );

  testWidgets('PageStorage restores each room after switching back and forth', (
    tester,
  ) async {
    final a = controllerOf(items(300));
    final b = controllerOf(items(300, from: 1000));
    final bucket = PageStorageBucket();
    Widget room(ReaderController<Item> c, String key) => PageStorage(
      bucket: bucket,
      child: host(
        c,
        ScrollController(),
        reverse: true,
        viewKey: PageStorageKey(key),
        heightOf: chatHeightOf,
      ),
    );
    await tester.pumpWidget(room(a, 'a'));
    await tester.pump();
    a.jumpToIndex(100, alignment: 0.5);
    await tester.pump();
    await tester.drag(find.byType(Scrollable), const Offset(0, 30));
    await tester.pumpAndSettle();
    final screenA = onScreen(tester);
    await tester.pumpWidget(room(b, 'b'));
    await tester.pump();
    expect(pixels(tester), 0.0, reason: 'room b starts at its end');
    b.jumpToId('item_1200');
    await tester.pump();
    await tester.pumpAndSettle();
    final screenB = onScreen(tester);
    await tester.pumpWidget(room(a, 'a'));
    await tester.pump();
    expect(onScreen(tester), screenA, reason: 'room a comes back as left');
    await tester.pumpWidget(room(b, 'b'));
    await tester.pump();
    expect(onScreen(tester), screenB, reason: 'room b comes back as left');
    a.dispose();
    b.dispose();
  });

  testWidgets(
    'PageStorage brings the same content back after heights changed',
    (tester) async {
      var tall = <int>{};
      double heightOf(Item item) =>
          tall.contains(item.n) ? 200 : chatHeightOf(item);
      final a = controllerOf(items(300));
      final bucket = PageStorageBucket();
      Widget room({required bool open}) => PageStorage(
        bucket: bucket,
        child: open
            ? host(
                a,
                ScrollController(),
                reverse: true,
                viewKey: const PageStorageKey('a'),
                heightOf: heightOf,
              )
            : const SizedBox(),
      );
      await tester.pumpWidget(room(open: true));
      await tester.pump();
      a.jumpToIndex(150, alignment: 0.4);
      await tester.pump();
      await tester.pump();
      final before = rows(tester);
      await tester.pumpWidget(room(open: false));
      // Everything above the remembered screenful grows while away.
      tall = {for (var i = 0; i < 140; i++) i};
      a.setItems(a.items.toList());
      await tester.pumpWidget(room(open: true));
      await tester.pump();
      await tester.pump();
      expect(rows(tester).first.$1, before.first.$1, reason: 'same first item');
      expect(rows(tester).first.$2, before.first.$2, reason: 'same offset');
      a.dispose();
    },
  );

  testWidgets('semantic indices stay in data order after diffs', (
    tester,
  ) async {
    final controller = controllerOf(items(30));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    List<(String, int)> indices() => [
      for (final element in find.byType(IndexedSemantics).evaluate())
        (
          find
              .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(Text),
              )
              .evaluate()
              .map((e) => (e.widget as Text).data!)
              .first,
          (element.widget as IndexedSemantics).index,
        ),
    ];
    for (final (id, index) in indices()) {
      expect(index, controller.indexOfId(id));
    }
    controller.setItems([
      ...items(2, from: 100),
      ...controller.items.where((i) => i.n != 28),
      const Item(200),
    ]);
    await tester.pump();
    for (final (id, index) in indices()) {
      expect(index, controller.indexOfId(id), reason: id);
    }
    controller.dispose();
    scroll.dispose();
  });

  testWidgets(
    'a scroll through 5,000 items keeps a screenful of widgets alive',
    (tester) async {
      final controller = controllerOf(items(5000));
      final scroll = ScrollController();
      await tester.pumpWidget(host(controller, scroll));
      await tester.pump();
      for (var i = 0; i < 5000; i += 100) {
        controller.jumpToIndex(i);
        await tester.pump();
      }
      await tester.fling(find.byType(Scrollable), const Offset(0, -2000), 4000);
      await tester.pumpAndSettle();
      expect(find.byType(Text).evaluate().length, lessThan(40));
      controller.dispose();
      scroll.dispose();
    },
  );
}
