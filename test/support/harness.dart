/// Shared fixtures for the widget-level tests: a 50 px item list in an
/// 800 × 600 window, and probes for what is on screen.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A test item: its id is `item_<n>`.
class const Item(final int n, {final String type = 'item'}) {
  String get id => 'item_$n';

  @override
  bool operator ==(Object other) =>
      other is Item && other.n == n && other.type == type;

  @override
  int get hashCode => Object.hash(n, type);

  @override
  String toString() => id;
}

final Map<String, ItemTypeConfig<Item>> itemConfigs = {
  'item': const ItemTypeConfig<Item>(
    typeName: 'item',
    defaultHeight: 50,
    defaultConfidence: 0.5,
  ),
  'divider': const ItemTypeConfig<Item>(
    typeName: 'divider',
    defaultHeight: 20,
    defaultConfidence: 0.95,
    widthSensitivity: WidthSensitivity.invariant,
  ),
};

List<Item> items(int count, {int from = 0}) => [
  for (var i = 0; i < count; i++) Item(from + i),
];

ReaderController<Item> controllerOf(
  List<Item> list, {
  bool hasMoreBefore = false,
  bool hasMoreAfter = false,
  double atEndThreshold = 0,
  void Function(LoadDirection direction)? onEdgeReached,
  ValueChanged<bool>? onAtEndChanged,
}) => ReaderController<Item>(
  items: list,
  idOf: (item) => item.id,
  typeKeyOf: (item) => item.type,
  typeConfigs: itemConfigs,
  initialWidth: 800,
  hasMoreBefore: hasMoreBefore,
  hasMoreAfter: hasMoreAfter,
  atEndThreshold: atEndThreshold,
  onEdgeReached: onEdgeReached,
  onAtEndChanged: onAtEndChanged,
);

/// The height of [item] under [heightOf], 50 by default.
typedef HeightOf = double Function(Item item);

Widget host(
  ReaderController<Item> controller,
  ScrollController scroll, {
  bool reverse = false,
  ReaderAnchor? anchor,
  HeightOf? heightOf,
  double width = 800,
  double height = 600,
  VoidCallback? onBuild,
  List<Widget> leadingSlivers = const [],
  List<Widget> trailingSlivers = const [],
  Listenable? itemUpdateListenable,
  bool addAutomaticKeepAlives = false,
  ScrollPhysics? physics,
  EdgeInsetsGeometry? padding,
  TextDirection textDirection = TextDirection.ltr,
  Key? viewKey,
  ValueChanged<String>? onAnchorPlaced,
}) => Directionality(
  textDirection: textDirection,
  child: Align(
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: width,
      height: height,
      child: ReaderView<Item>(
        key: viewKey,
        controller: controller,
        scrollController: scroll,
        reverse: reverse,
        anchor: anchor,
        leadingSlivers: leadingSlivers,
        trailingSlivers: trailingSlivers,
        itemUpdateListenable: itemUpdateListenable,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        physics: physics,
        padding: padding,
        onAnchorPlaced: onAnchorPlaced,
        itemBuilder: (context, index, item) {
          onBuild?.call();
          return SizedBox(
            height: heightOf?.call(item) ?? 50,
            child: Text(item.id),
          );
        },
      ),
    ),
  ),
);

/// The viewport's scroll offset.
double pixels(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

/// The rendered item texts with their top edge and height in the 600 px
/// window, top to bottom.
List<(String id, double top, double height)> rows(WidgetTester tester) {
  final out = <(String, double, double)>[];
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || !box.attached) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    final height = box.size.height;
    if (top + height <= 0 || top >= 600) continue;
    out.add(((element.widget as Text).data!, top, height));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// The rendered item texts with their top edge in the 600 px window,
/// top to bottom.
List<(String id, double top)> onScreen(WidgetTester tester) => [
  for (final (id, top, _) in rows(tester)) (id, top),
];

/// The id at the top of the window and its top edge.
(String id, double top) topOfScreen(WidgetTester tester) =>
    onScreen(tester).first;

/// The id at the bottom of the window and its top edge.
(String id, double top) bottomOfScreen(WidgetTester tester) =>
    onScreen(tester).last;

/// The top edge of [id] on screen, or null when it is not rendered.
double? topOf(WidgetTester tester, String id) {
  for (final (rowId, top) in onScreen(tester)) {
    if (rowId == id) return top;
  }
  return null;
}
