/// README claims: edge loading fires once per page when the loaded edge
/// enters the cache window, never at open for a long history, and the
/// at-end threshold drives [ReaderController.isAtEnd].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('reverse: a long history does not load older at open', (
    tester,
  ) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(
      items(100),
      hasMoreBefore: true,
      onEdgeReached: fired.add,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    await tester.pump();
    expect(fired, isEmpty);
    await tester.drag(find.byType(Scrollable), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: 'the oldest item is 5,000 px away');
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('reverse: older loads once per page when the top is reached', (
    tester,
  ) async {
    final fired = <LoadDirection>[];
    late ReaderController<Item> controller;
    var next = 1000;
    controller = controllerOf(
      items(100),
      hasMoreBefore: true,
      onEdgeReached: (direction) {
        fired.add(direction);
        controller.setItems([...items(20, from: next), ...controller.items]);
        next += 20;
      },
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    controller.jumpToIndex(2);
    await tester.pump(); // layout + report
    await tester.pump(); // the page lands
    expect(fired, [LoadDirection.before]);
    expect(controller.itemCount, 120);
    await tester.pump();
    expect(fired.length, 1, reason: 'the new oldest is a page away');
    controller.jumpToIndex(1);
    await tester.pump();
    await tester.pump();
    expect(fired.length, 2);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('a short history loads older at open', (tester) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(
      items(5),
      hasMoreBefore: true,
      onEdgeReached: fired.add,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(fired, [LoadDirection.before]);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('the guard holds until the edge gains items', (tester) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(
      items(5),
      hasMoreBefore: true,
      onEdgeReached: fired.add,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(fired.length, 1);
    await tester.drag(find.byType(Scrollable), const Offset(0, 10));
    await tester.pumpAndSettle();
    expect(fired.length, 1, reason: 'no re-fire while the page is loading');
    controller.prependItems(const []); // a failed load resets the guard
    await tester.pump();
    await tester.pump();
    expect(fired.length, 2);
    controller.prependItems(items(3, from: 100));
    await tester.pump();
    await tester.pump();
    expect(fired.length, 3, reason: 'the edge is still inside the window');
    controller.hasMoreBefore = false;
    controller.prependItems(const []);
    await tester.pump();
    await tester.pump();
    expect(fired.length, 3);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('forward: the end loads more', (tester) async {
    final fired = <LoadDirection>[];
    final controller = controllerOf(
      items(100),
      hasMoreAfter: true,
      onEdgeReached: fired.add,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    expect(fired, isEmpty);
    controller.scrollToEnd();
    await tester.pump();
    await tester.pump();
    expect(fired, [LoadDirection.after]);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('reverse: isAtEnd follows the threshold', (tester) async {
    final changes = <bool>[];
    final controller = controllerOf(
      items(100),
      atEndThreshold: 48,
      onAtEndChanged: changes.add,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll, reverse: true));
    await tester.pump();
    expect(controller.isAtEnd, isTrue);
    expect(changes, isEmpty);
    scroll.jumpTo(30);
    await tester.pump();
    expect(controller.isAtEnd, isTrue);
    scroll.jumpTo(60);
    await tester.pump();
    expect(controller.isAtEnd, isFalse);
    expect(changes, [false]);
    scroll.jumpTo(0);
    await tester.pump();
    expect(changes, [false, true]);
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('forward: the end is the last item', (tester) async {
    final controller = controllerOf(items(100), atEndThreshold: 48);
    final scroll = ScrollController();
    await tester.pumpWidget(host(controller, scroll));
    await tester.pump();
    await tester.pump();
    expect(controller.isAtEnd, isFalse);
    controller.scrollToEnd();
    await tester.pump();
    await tester.pump();
    expect(controller.isAtEnd, isTrue);
    controller.dispose();
    scroll.dispose();
  });
}
