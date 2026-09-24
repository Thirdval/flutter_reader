/// A model-based random walk over the sliver: random drags, jumps,
/// inserts, removals, edits and anchors, with invariants checked after
/// every step in both directions.
library;

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _viewport = 600.0;

class _World(final int seed, final bool reverse) {
  late final Random random = Random(seed);
  final Map<int, int> edits = {};
  int next = 300;
  ReaderAnchor? anchor;
  late ReaderController<Item> controller;
  late ScrollController scroll;

  /// Real heights: 20..119, changed by an edit.
  double heightOf(Item item) =>
      20 + ((item.n * 7919 + (edits[item.n] ?? 0) * 104729) % 100).toDouble();

  Widget build() => host(
    controller,
    scroll,
    reverse: reverse,
    anchor: anchor,
    heightOf: heightOf,
    trailingSlivers: const [SliverToBoxAdapter(child: SizedBox(height: 32))],
    leadingSlivers: const [SliverToBoxAdapter(child: SizedBox(height: 4))],
  );
}

/// Rows must tile the screen with no gap or overlap, in data order.
void _checkTiling(WidgetTester tester, _World w, String step) {
  final r = rows(tester);
  expect(r, isNotEmpty, reason: '$step: nothing on screen');
  for (var i = 0; i + 1 < r.length; i++) {
    final (id, top, height) = r[i];
    final (nextId, nextTop, _) = r[i + 1];
    expect(
      nextTop,
      closeTo(top + height, 0.01),
      reason: '$step: gap between $id and $nextId',
    );
    // Top to bottom is ascending in both modes: a reversed list keeps
    // older items above newer ones.
    expect(
      w.controller.indexOfId(nextId),
      w.controller.indexOfId(id)! + 1,
      reason: '$step: $id and $nextId are not neighbours',
    );
  }
  // The screen is covered from the first row's top to the last row's
  // bottom, unless the list ends inside the viewport.
  final first = r.first;
  final last = r.last;
  final firstIndex = w.controller.indexOfId(first.$1)!;
  final lastIndex = w.controller.indexOfId(last.$1)!;
  final count = w.controller.itemCount;
  // Rows ascend top to bottom in both modes; the spacer sits at the
  // origin edge (4 px).
  final topIsEdge = firstIndex == 0;
  final bottomIsEdge = lastIndex == count - 1;
  if (!topIsEdge && first.$2 > 0.01) {
    fail('$step: ${first.$1} starts at ${first.$2} with items above it');
  }
  if (!bottomIsEdge && last.$2 + last.$3 < _viewport - 0.01) {
    fail('$step: ${last.$1} ends at ${last.$2 + last.$3} with items below it');
  }
}

Future<void> _walk(WidgetTester tester, _World w, {int steps = 120}) async {
  w.controller = controllerOf(items(300), hasMoreBefore: true);
  w.scroll = ScrollController();
  await tester.pumpWidget(w.build());
  await tester.pump();
  _checkTiling(tester, w, 'start');
  for (var step = 0; step < steps; step++) {
    final before = rows(tester);
    final atEnd = w.controller.isAtEnd;
    final op = w.random.nextInt(10);
    final label =
        'seed ${w.seed} ${w.reverse ? "reverse" : "forward"} step $step op $op';
    var strict = false; // nothing visible may move
    var settled = false; // the position went through a ballistic end
    switch (op) {
      case 0 || 1 || 2:
        final dy = (w.random.nextDouble() * 800 - 400).roundToDouble();
        await tester.drag(find.byType(Scrollable), Offset(0, dy));
        await tester.pump();
        if (w.random.nextBool()) {
          await tester.pumpAndSettle();
          settled = true;
        }
      case 3:
        final position = w.scroll.position;
        w.scroll.jumpTo(w.random.nextDouble() * position.maxScrollExtent);
        await tester.pump();
      case 4:
        final index = w.random.nextInt(w.controller.itemCount);
        final alignment = w.random.nextInt(4) / 4;
        w.controller.jumpToIndex(index, alignment: alignment);
        await tester.pump();
        final id = w.controller.itemAt(index).id;
        expect(
          topOf(tester, id),
          isNotNull,
          reason: '$label: jump to $id not on screen',
        );
        await tester.pump();
        expect(
          w.controller.visibility.value.contains(index),
          isTrue,
          reason: '$label: visibility',
        );
      case 5 || 6:
        // A mutation somewhere: outside the visible range it must not move
        // anything on screen (unless follow mode pins the changing end).
        final list = w.controller.items.toList();
        final visibleIds = [for (final (id, _, _) in before) id];
        final vis = [for (final id in visibleIds) w.controller.indexOfId(id)!];
        final low = vis.reduce(min);
        final high = vis.reduce(max);
        final kind = w.random.nextInt(3);
        int at;
        if (kind == 0) {
          // remove 1..3 items at a random position
          at = w.random.nextInt(list.length);
          final n = min(1 + w.random.nextInt(3), list.length - at);
          strict =
              (at + n - 1 < low || at > high) &&
              !(atEnd && _touchesPinnedEnd(w, at, at + n, list.length));
          list.removeRange(at, at + n);
        } else if (kind == 1) {
          // insert 1..3 items at a random position (ends included)
          at = w.random.nextInt(list.length + 1);
          final fresh = [
            for (var i = 0; i < 1 + w.random.nextInt(3); i++) Item(w.next++),
          ];
          strict =
              (at <= low || at > high) &&
              !(atEnd && _touchesPinnedEnd(w, at, at, list.length));
          list.insertAll(at, fresh);
        } else {
          // edit an item's height
          at = w.random.nextInt(list.length);
          strict =
              (at < low || at > high) &&
              !(atEnd && _touchesPinnedEnd(w, at, at + 1, list.length));
          w.edits[list[at].n] = (w.edits[list[at].n] ?? 0) + 1;
          list[at] = Item(list[at].n); // same id, "new" payload
        }
        if (w.anchor != null && !list.any((i) => i.id == w.anchor!.id)) {
          strict = false;
        }
        w.controller.setItems(list);
        await tester.pump();
        if (strict) {
          final after = {for (final (id, top, _) in rows(tester)) id: top};
          for (final (id, top, _) in before) {
            if (after.containsKey(id)) {
              expect(
                after[id],
                closeTo(top, 0.01),
                reason:
                    '$label ($kind at $at, visible $low..$high, atEnd $atEnd): $id moved',
              );
            }
          }
        }
        await tester.pump();
      case 7:
        // anchor set / clear
        if (w.anchor == null || w.random.nextBool()) {
          final index = w.random.nextInt(w.controller.itemCount);
          w.anchor = ReaderAnchor(
            id: w.controller.itemAt(index).id,
            alignment: w.random.nextInt(4) / 4,
          );
        } else {
          w.anchor = null;
        }
        await tester.pumpWidget(w.build());
        await tester.pump();
      case 8:
        w.controller.scrollToEnd();
        await tester.pump();
        final lastId = w.controller.itemAt(w.controller.itemCount - 1).id;
        final row = rows(tester).where((r) => r.$1 == lastId).firstOrNull;
        expect(row, isNotNull, reason: '$label: scrollToEnd');
        // In reverse the 4 px spacer sits below the last item.
        expect(
          row!.$2 + row.$3,
          closeTo(_viewport - (w.reverse ? 4 : 0), 0.01),
          reason: '$label: last item flush with the end',
        );
      case _:
        // a fling
        await tester.fling(
          find.byType(Scrollable),
          Offset(0, w.random.nextBool() ? -900 : 900),
          2000,
        );
        await tester.pumpAndSettle();
        settled = true;
    }
    _checkTiling(tester, w, label);
    // An offset past a shrunken extent stays there until a gesture's
    // ballistic end springs it back, as in any dead-reckoning list.
    if (settled) {
      final position = w.scroll.position;
      expect(
        position.pixels,
        greaterThanOrEqualTo(position.minScrollExtent - 0.01),
        reason: '$label: below min',
      );
      expect(
        position.pixels,
        lessThanOrEqualTo(position.maxScrollExtent + 0.01),
        reason: '$label: above max',
      );
    }
  }
  // Settle at both ends: the origin is exact once reached.
  w.anchor = null;
  await tester.pumpWidget(w.build());
  w.scroll.jumpTo(0);
  await tester.pump();
  await tester.pump();
  final endId = w.controller
      .itemAt(w.reverse ? w.controller.itemCount - 1 : 0)
      .id;
  final endRow = rows(tester).firstWhere((r) => r.$1 == endId);
  if (w.reverse) {
    expect(
      endRow.$2 + endRow.$3,
      closeTo(_viewport - 4, 0.01),
      reason: 'origin (reverse) after the walk',
    );
  } else {
    expect(
      endRow.$2,
      closeTo(4, 0.01),
      reason: 'origin (forward) after the walk',
    );
  }
  w.controller.dispose();
  w.scroll.dispose();
}

/// In follow mode the pinned end is data index 0 (forward) or the last
/// item (reverse); a change at or beyond it legitimately shifts content.
bool _touchesPinnedEnd(_World w, int from, int to, int count) =>
    w.reverse ? to >= count : from <= 0;

void main() {
  for (final reverse in [false, true]) {
    for (final seed in [1, 2, 3, 4, 5]) {
      testWidgets('random walk ${reverse ? "reverse" : "forward"} seed $seed', (
        tester,
      ) async {
        await _walk(tester, _World(seed, reverse));
      });
    }
  }
}
