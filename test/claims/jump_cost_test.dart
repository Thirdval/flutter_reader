/// README claim: a jump to any item builds only the viewport and its
/// cache window, never what lies between.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'jumping from item 0 to item 5,000 of 10,000 builds a screenful',
    (tester) async {
      var builds = 0;
      final controller = controllerOf(items(10000));
      final scroll = ScrollController();
      await tester.pumpWidget(
        host(controller, scroll, onBuild: () => builds++),
      );
      await tester.pump();
      final before = builds;
      controller.jumpToIndex(5000);
      await tester.pump();
      expect(builds - before, lessThan(40));
      expect(topOfScreen(tester), ('item_5000', 0.0));
      expect(pixels(tester), 5000 * 50.0);
      controller.dispose();
      scroll.dispose();
    },
  );

  testWidgets('a jump lands the item at the alignment, in reverse too', (
    tester,
  ) async {
    final controller = controllerOf(items(1000));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    controller.jumpToId('item_500', alignment: 0.7);
    await tester.pump();
    // In reverse the leading edge is the bottom: the item's bottom sits
    // 70 % of the viewport up from the bottom edge, so its top is at
    // 600 − 420 − 50 = 130.
    expect(topOf(tester, 'item_500'), 130.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a jump requested before the first layout waits for it', (
    tester,
  ) async {
    final controller = controllerOf(items(1000));
    final scroll = ScrollController();
    controller.jumpToIndex(300);
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    expect(topOfScreen(tester), ('item_300', 0.0));
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('scrollToEnd shows the last item in both directions', (
    tester,
  ) async {
    for (final reverse in [false, true]) {
      final controller = controllerOf(items(200));
      final scroll = ScrollController();
      await tester.pumpWidget(host(controller, scroll, reverse: reverse));
      await tester.pump();
      controller.jumpToIndex(20);
      await tester.pump();
      controller.scrollToEnd();
      await tester.pump();
      expect(topOf(tester, 'item_199'), 550.0, reason: 'reverse: $reverse');
      expect(controller.isAtEnd, isTrue);
      controller.dispose();
      scroll.dispose();
    }
  });
}
