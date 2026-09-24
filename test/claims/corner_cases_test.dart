/// Corner cases the render object must survive: inserts inside and just
/// above the visible range (gaps between attached children), items
/// taller than the viewport, zero-height items, keep-alives, padding,
/// bouncing physics, RTL, restore from PageStorage, rapid jumps, an
/// anchored item that vanishes, and an emptied list.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('an insert inside the visible range fills the gap', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    scroll.jumpTo(1000);
    await tester.pump();
    final list = controller.items.toList()..insert(25, const Item(500));
    controller.setItems(list);
    await tester.pump();
    expect(topOf(tester, 'item_24'), 200.0);
    expect(topOf(tester, 'item_500'), 250.0);
    expect(topOf(tester, 'item_25'), 300.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('an insert just above the first visible item moves nothing', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    scroll.jumpTo(1000);
    await tester.pump();
    final before = onScreen(tester);
    final list = controller.items.toList()..insert(20, const Item(500));
    controller.setItems(list);
    await tester.pump();
    expect(onScreen(tester), before);
    scroll.jumpTo(950);
    await tester.pump();
    expect(topOf(tester, 'item_500'), 0.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('items taller than the viewport scroll through', (tester) async {
    double heightOf(Item item) => item.n == 10 ? 3000 : 50;
    final controller = controllerOf(items(30));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, heightOf: heightOf));
    await tester.pump();
    controller.jumpToIndex(10, alignment: 0);
    await tester.pump();
    expect(topOf(tester, 'item_10'), 0.0);
    scroll.jumpTo(pixels(tester) + 1500);
    await tester.pump();
    expect(topOf(tester, 'item_10'), -1500.0);
    expect(rows(tester).length, 1);
    scroll.jumpTo(pixels(tester) + 1500);
    await tester.pump();
    expect(topOf(tester, 'item_11'), 0.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('zero-height items are tolerated', (tester) async {
    double heightOf(Item item) => item.n.isEven ? 0 : 50;
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, heightOf: heightOf),
    );
    await tester.pump();
    controller.jumpToIndex(2, alignment: 0.5);
    await tester.pump();
    expect(controller.visibility.value.contains(2), isTrue);
    scroll.jumpTo(0);
    await tester.pump();
    expect(topOf(tester, 'item_99'), 550.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('keep-alives survive scrolling away and back', (tester) async {
    final controller = controllerOf(items(200));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, addAutomaticKeepAlives: true),
    );
    await tester.pump();
    controller.jumpToIndex(150);
    await tester.pump();
    controller.jumpToIndex(0);
    await tester.pump();
    expect(topOfScreen(tester), ('item_0', 0.0));
    scroll.jumpTo(300);
    await tester.pump();
    expect(topOfScreen(tester), ('item_6', 0.0));
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('padding and an anchor', (tester) async {
    final controller = controllerOf(items(200));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 24),
        anchor: const ReaderAnchor(id: 'item_100', alignment: 0.7),
      ),
    );
    await tester.pump();
    expect(topOf(tester, 'item_100'), 130.0);
    scroll.jumpTo(0);
    await tester.pump();
    expect(topOf(tester, 'item_199'), 600 - 24 - 50);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('bouncing physics: overscroll at both ends settles back', (
    tester,
  ) async {
    final controller = controllerOf(items(50), atEndThreshold: 48);
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        physics: const BouncingScrollPhysics(),
      ),
    );
    await tester.pump();
    await tester.fling(find.byType(Scrollable), const Offset(0, -400), 3000);
    await tester.pumpAndSettle();
    expect(pixels(tester), 0.0);
    expect(controller.isAtEnd, isTrue);
    expect(topOf(tester, 'item_49'), 550.0);
    await tester.fling(find.byType(Scrollable), const Offset(0, 5000), 8000);
    await tester.pumpAndSettle();
    expect(pixels(tester), scroll.position.maxScrollExtent);
    expect(topOf(tester, 'item_0'), 0.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('RTL renders the same vertical list', (tester) async {
    final controller = controllerOf(items(30));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, textDirection: TextDirection.rtl),
    );
    await tester.pump();
    expect(topOfScreen(tester), ('item_0', 0.0));
    controller.jumpToIndex(20);
    await tester.pump();
    expect(topOfScreen(tester), ('item_20', 0.0));
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a PageStorageKey restores the offset after a rebuild', (
    tester,
  ) async {
    final controller = controllerOf(items(200));
    final bucket = PageStorageBucket();
    Widget page({required bool showList}) => PageStorage(
      bucket: bucket,
      child: showList
          ? host(
              controller,
              ScrollController(),
              viewKey: const PageStorageKey('room'),
            )
          : const SizedBox(),
    );
    await tester.pumpWidget(page(showList: true));
    await tester.pump();
    controller.jumpToIndex(60);
    await tester.pump();
    await tester.drag(find.byType(Scrollable), const Offset(0, -25));
    await tester.pumpAndSettle();
    final offset = pixels(tester);
    final before = onScreen(tester);
    await tester.pumpWidget(page(showList: false));
    await tester.pumpWidget(page(showList: true));
    await tester.pump();
    expect(pixels(tester), offset);
    expect(onScreen(tester), before);
    controller.dispose();
  });

  testWidgets('two jumps in one frame: the last one wins', (tester) async {
    final controller = controllerOf(items(1000));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    controller
      ..jumpToIndex(300)
      ..jumpToIndex(700, alignment: 0.5);
    await tester.pump();
    expect(topOf(tester, 'item_700'), 300.0);
    expect(find.text('item_300'), findsNothing);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('an anchored item that vanishes releases the anchor cleanly', (
    tester,
  ) async {
    final controller = controllerOf(items(200));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_100', alignment: 0.5),
      ),
    );
    await tester.pump();
    final aboveTop = topOf(tester, 'item_99')!;
    final belowTop = topOf(tester, 'item_101')!;
    controller.setItems([
      for (final i in controller.items)
        if (i.n != 100) i,
    ]);
    await tester.pump();
    expect(find.text('item_100'), findsNothing);
    // The survivor further from the origin holds (above, in reverse);
    // the newer side closes the gap.
    expect(topOf(tester, 'item_99'), aboveTop, reason: 'the item above holds');
    expect(
      topOf(tester, 'item_101'),
      belowTop - 50,
      reason: 'the item below closes the gap',
    );
    controller.setItems([
      ...controller.items.take(100),
      const Item(100),
      ...controller.items.skip(100),
    ]);
    await tester.pump();
    expect(
      topOf(tester, 'item_100'),
      250.0,
      reason: 'the anchor is placed again when it returns',
    );
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('emptying and refilling the list', (tester) async {
    final controller = controllerOf(items(50));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    controller.setItems(const []);
    await tester.pump();
    expect(find.byType(Text), findsNothing);
    controller.setItems(items(10));
    await tester.pump();
    expect(topOf(tester, 'item_9'), 550.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('hasMoreBefore flipped on later fires for a reached edge', (
    tester,
  ) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(items(5), onEdgeReached: fired.add);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(fired, isEmpty);
    controller.hasMoreBefore = true;
    await tester.pump();
    expect(fired, [LoadDirection.before]);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('animateToId lands exactly across unmeasured regions', (
    tester,
  ) async {
    double heightOf(Item item) => item.n.isEven ? 30 : 90;
    final controller = controllerOf(items(500));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, heightOf: heightOf),
    );
    await tester.pump();
    final future = controller.animateToId('item_200', alignment: 0.5);
    await tester.pumpAndSettle();
    await future;
    await tester.pump();
    expect(topOf(tester, 'item_200'), 600 - 300 - 30);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('semantic indices count in data order in reverse', (
    tester,
  ) async {
    final controller = controllerOf(items(30));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    final indices = [
      for (final element in find.byType(IndexedSemantics).evaluate())
        (element.widget as IndexedSemantics).index,
    ];
    expect(indices, isNotEmpty);
    expect(indices.reduce((a, b) => a > b ? a : b), 29);
    expect(indices.toSet().length, indices.length);
    controller.dispose();
    scroll.dispose();
  });
}
