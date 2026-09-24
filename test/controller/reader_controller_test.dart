import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  test('exposes items in data order', () {
    final controller = controllerOf(items(3));
    expect(controller.itemCount, 3);
    expect(controller.itemAt(1), const Item(1));
    expect(controller.indexOfId('item_2'), 2);
    expect(controller.indexOfId('nope'), isNull);
    expect(controller.items.map((i) => i.n), [0, 1, 2]);
    controller.dispose();
  });

  test('setItems keeps heights by id and refreshes payloads', () {
    final controller = controllerOf(items(3));
    controller.registry.reportMeasuredHeight(1, 123);
    controller.setItems([
      const Item(0),
      const Item(1, type: 'divider'),
      const Item(9),
    ]);
    expect(controller.itemCount, 3);
    expect(controller.registry.heightAt(1), 123, reason: 'item_1 survived');
    expect(controller.itemAt(1).type, 'divider', reason: 'payload refreshed');
    expect(controller.indexOfId('item_2'), isNull);
    expect(controller.indexOfId('item_9'), 2);
    controller.dispose();
  });

  test('batch mutations notify once each', () {
    final controller = controllerOf(items(3));
    var notified = 0;
    controller.addListener(() => notified++);
    controller.appendItems(items(2, from: 3));
    controller.prependItems(items(1, from: 10));
    controller.insertItems(2, items(1, from: 20));
    controller.removeItems(0, 1);
    controller.updateItem(0, const Item(0, type: 'divider'));
    expect(notified, 5);
    expect(controller.items.map((i) => i.id), [
      'item_0',
      'item_20',
      'item_1',
      'item_2',
      'item_3',
      'item_4',
    ]);
    expect(controller.itemAt(0).type, 'divider');
    controller.dispose();
  });

  test('jumps before attach are remembered, unknown ids ignored', () {
    final controller = controllerOf(items(3));
    controller.jumpToId('item_2', alignment: 0.5);
    expect(controller.pendingJump?.id, 'item_2');
    controller.jumpToId('nope');
    expect(controller.pendingJump?.id, 'item_2');
    controller.dispose();
  });

  test('the engine and the registry share the items', () {
    final controller = controllerOf(items(3));
    expect(controller.engine.itemCount, 3);
    expect(controller.engine.itemAt(2).id, 'item_2');
    controller.dispose();
  });

  testWidgets('animateToId lands exactly', (tester) async {
    final controller = controllerOf(items(500));
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    final future = controller.animateToId('item_300', alignment: 0.25);
    await tester.pumpAndSettle();
    await future;
    await tester.pump();
    expect(topOf(tester, 'item_300'), 150.0);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('animateToEnd reaches the end in both directions', (
    tester,
  ) async {
    for (final reverse in [true, false]) {
      final controller = controllerOf(items(100));
      final scroll = ScrollController();
      await tester.pumpWidget(host(controller, scroll, reverse: reverse));
      await tester.pump();
      controller.jumpToIndex(30);
      await tester.pump();
      final future = controller.animateToEnd();
      await tester.pumpAndSettle();
      await future;
      await tester.pump();
      expect(controller.isAtEnd, isTrue, reason: 'reverse $reverse');
      expect(topOf(tester, 'item_99'), 550.0);
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets('swapping controllers and scroll controllers re-attaches', (
    tester,
  ) async {
    final a = controllerOf(items(5));
    final b = controllerOf(items(3));
    final scroll = ScrollController();
    await tester.pumpWidget(host(a, scroll));
    await tester.pump();
    expect(find.text('item_4'), findsOneWidget);
    await tester.pumpWidget(host(b, scroll));
    await tester.pump();
    expect(find.text('item_4'), findsNothing);
    expect(find.text('item_2'), findsOneWidget);
    final scroll2 = ScrollController();
    await tester.pumpWidget(host(b, scroll2));
    await tester.pump();
    expect(find.text('item_2'), findsOneWidget);
    a.dispose();
    b.dispose();
    scroll.dispose();
    scroll2.dispose();
  });

  testWidgets('an itemUpdateListenable rebuilds visible items', (tester) async {
    final controller = controllerOf(items(5));
    final scroll = ScrollController();
    final tick = ValueNotifier<int>(0);
    var builds = 0;
    await tester.pumpWidget(
      host(
        controller,
        scroll,
        itemUpdateListenable: tick,
        onBuild: () => builds++,
      ),
    );
    await tester.pump();
    final before = builds;
    tick.value = 1;
    await tester.pump();
    expect(builds - before, 5);
    controller.dispose();
    scroll.dispose();
    tick.dispose();
  });
}
