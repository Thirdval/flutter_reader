/// README claim: an anchored item stays at its alignment while pages load
/// around it, and is placed as soon as it appears.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'the anchor holds at 0.7 through ten older pages and new messages',
    (tester) async {
      double heightOf(Item item) => item.n.isEven ? 30 : 90; // estimates say 50
      final controller = controllerOf(items(100), hasMoreBefore: true);
      final scroll = ScrollController();
      const anchor = ReaderAnchor(id: 'item_50', alignment: 0.7);
      await tester.pumpWidget(
        host(
          controller,
          scroll,
          reverse: true,
          anchor: anchor,
          heightOf: heightOf,
        ),
      );
      await tester.pump();
      // The bottom edge of item_50 (30 px, an even n) sits 420 px up from
      // the bottom of the 600 px window.
      expect(topOf(tester, 'item_50'), 600 - 420 - 30);
      final before = onScreen(tester);
      for (var page = 0; page < 10; page++) {
        controller.setItems([
          ...items(50, from: 1000 + page * 50),
          ...controller.items,
        ]);
        await tester.pump();
        await tester.pump();
      }
      controller.setItems([...controller.items, ...items(5, from: 5000)]);
      await tester.pump();
      await tester.pump();
      expect(onScreen(tester), before);
      expect(controller.itemCount, 605);
      controller.dispose();
      scroll.dispose();
    },
  );

  testWidgets('an anchor on an item not loaded yet is placed when it lands', (
    tester,
  ) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    const anchor = ReaderAnchor(id: 'item_500', alignment: 0.7);
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, anchor: anchor),
    );
    await tester.pump();
    expect(bottomOfScreen(tester), ('item_99', 550.0));
    controller.setItems([...items(100), ...items(500, from: 100)]);
    await tester.pump();
    await tester.pump();
    expect(topOf(tester, 'item_500'), 130.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('clearing the anchor moves nothing; jumpTo(0) is the end', (
    tester,
  ) async {
    final controller = controllerOf(items(200));
    final scroll = ScrollController();
    const anchor = ReaderAnchor(id: 'item_100', alignment: 0.7);
    await tester.pumpWidget(
      host(controller, scroll, reverse: true, anchor: anchor),
    );
    await tester.pump();
    final before = onScreen(tester);
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(onScreen(tester), before);
    scroll.jumpTo(0);
    await tester.pump();
    expect(bottomOfScreen(tester), ('item_199', 550.0));
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('leading slivers do not shift an anchor or a jump', (
    tester,
  ) async {
    for (final spacer in [4.0, 40.0]) {
      final controller = controllerOf(items(200));
      final scroll = ScrollController();
      final slivers = [SliverToBoxAdapter(child: SizedBox(height: spacer))];
      await tester.pumpWidget(
        host(
          controller,
          scroll,
          reverse: true,
          anchor: const ReaderAnchor(id: 'item_100', alignment: 0.7),
          leadingSlivers: slivers,
          trailingSlivers: const [
            SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      );
      await tester.pump();
      expect(topOf(tester, 'item_100'), 130.0, reason: 'spacer $spacer');
      controller.jumpToId('item_150', alignment: 0.5);
      await tester.pump();
      expect(topOf(tester, 'item_150'), 250.0, reason: 'spacer $spacer');
      scroll.jumpTo(0);
      await tester.pump();
      controller.jumpToId('item_190', alignment: 0.7);
      await tester.pump();
      expect(topOf(tester, 'item_190'), 130.0, reason: 'from the end');
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets('a second anchor re-places; the same anchor does not', (
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
    expect(topOf(tester, 'item_100'), 600 - 300 - 50);
    scroll.jumpTo(pixels(tester) + 100);
    await tester.pump();
    final moved = topOf(tester, 'item_100');
    expect(moved, 600 - 300 - 50 + 100);
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_100', alignment: 0.5),
      ),
    );
    await tester.pump();
    expect(topOf(tester, 'item_100'), moved, reason: 'unchanged anchor');
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        anchor: const ReaderAnchor(id: 'item_120', alignment: 0.5),
      ),
    );
    await tester.pump();
    expect(topOf(tester, 'item_120'), 600 - 300 - 50);
    controller.dispose();
    scroll.dispose();
  });
}
