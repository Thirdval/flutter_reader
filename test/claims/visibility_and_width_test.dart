/// README claims: visibility reports the items on screen in data order
/// in both directions, and a width change re-estimates heights.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('reverse visibility is the newest screenful', (tester) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    await tester.pump();
    expect(controller.visibility.value.firstVisible, 88);
    expect(controller.visibility.value.lastVisible, 99);
    scroll.jumpTo(500);
    await tester.pump();
    await tester.pump();
    expect(controller.visibility.value.firstVisible, 78);
    expect(controller.visibility.value.lastVisible, 89);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('forward visibility is the first screenful', (tester) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    var notified = 0;
    controller.visibility.addListener(() => notified++);
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    await tester.pump();
    expect(controller.visibility.value.firstVisible, 0);
    expect(controller.visibility.value.lastVisible, 11);
    expect(notified, 1);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a width change reaches the registry', (tester) async {
    final controller = controllerOf(items(30));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, width: 800));
    await tester.pump();
    expect(controller.registry.currentWidth, 800);
    await tester.pumpWidget(host(controller, scroll, width: 300));
    await tester.pump();
    expect(controller.registry.currentWidth, 300);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a width change keeps the top item in place', (tester) async {
    final controller = controllerOf(items(100));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    scroll.jumpTo(1000);
    await tester.pump();
    final before = onScreen(tester);
    await tester.pumpWidget(host(controller, scroll, width: 500));
    await tester.pump();
    expect(onScreen(tester), before);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('leading and trailing slivers render around the list', (
    tester,
  ) async {
    final controller = controllerOf(items(3));
    final scroll = ScrollController();
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        reverse: true,
        leadingSlivers: const [
          SliverToBoxAdapter(child: SizedBox(height: 4, child: Text('spacer'))),
        ],
        trailingSlivers: const [
          SliverToBoxAdapter(
            child: SizedBox(height: 40, child: Text('loader')),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(onScreen(tester).map((r) => r.$1), [
      'loader',
      'item_0',
      'item_1',
      'item_2',
      'spacer',
    ]);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('mutations render without a host rebuild', (tester) async {
    final controller = controllerOf(items(10));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    controller.appendItems(items(5, from: 10));
    await tester.pump();
    expect(find.text('item_11'), findsOneWidget);
    controller.removeItems(0, 12);
    await tester.pump();
    expect(find.text('item_11'), findsNothing);
    expect(find.text('item_12'), findsOneWidget);
    controller.dispose();
    scroll.dispose();
  });
}
