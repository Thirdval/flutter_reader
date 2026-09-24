# flutter_reader

An engine-backed scrollable list for Flutter: exact jumps to any item
without building what lies between, a reference item kept fixed while
content changes around it, a reverse (chat) mode, lazy loading gated on
the cache extent, and text search. Pure widgets, no Material: it renders
inside your design system.

Every claim below names the test that proves it.

## Install

```yaml
dependencies:
  flutter_reader:
    git:
      url: https://github.com/Thirdval/flutter_reader.git
      ref: v2.1.0
```

Dart `^3.13.0`, Flutter `>=3.47.0` (`.fvmrc` pins 3.47.1). No other
dependencies.

## A chat

```dart
final reader = ReaderController<Message>(
  items: messages,                   // oldest first
  idOf: (m) => m.id,                 // stable ids drive jumps and diffs
  typeKeyOf: (m) => m.typeKey,       // 'message' | 'day' | 'new'
  typeConfigs: {
    'message': const ItemTypeConfig<Message>(typeName: 'message', defaultHeight: 72),
    'day': const ItemTypeConfig<Message>(
      typeName: 'day', defaultHeight: 40, defaultConfidence: 0.95,
      widthSensitivity: WidthSensitivity.invariant,
    ),
  },
  initialWidth: width,
  hasMoreBefore: hasOlder,           // the older end is data index 0
  onEdgeReached: (_) => loadOlder(), // once per page, after the frame
  atEndThreshold: 48,
  onAtEndChanged: (atEnd) => markRead(atEnd),
);

ReaderView<Message>(
  key: PageStorageKey('room-${room.id}'),      // the same content comes back
  controller: reader,
  scrollController: scrollController,          // yours; jumpTo(0) is "latest"
  reverse: true,
  anchor: target == null ? null : ReaderAnchor(id: target, alignment: 0.7),
  onAnchorPlaced: (id) => startHighlight(id),  // when it is on screen
  leadingSlivers: [const SliverToBoxAdapter(child: SizedBox(height: 4))],
  trailingSlivers: [SliverToBoxAdapter(child: historyLoaderOrIntro)],
  itemBuilder: (context, index, message) => MessageBubble(message),
);

// On every emission of the watched feed:
reader.setItems(messages, hasMoreBefore: hasOlder);
```

* `setItems` diffs by id: survivors keep their measured heights and get
  the new payload, removals and insertions apply as batches, and only
  items that changed relative order are re-inserted. What is on screen
  does not move.
* At the end of the list (within `atEndThreshold`) a new message pushes
  in; scrolled up, nothing moves and your "new below" count works.
* `anchor` pins an item's leading edge at `alignment` (a fraction of the
  viewport from its leading edge, the bottom in reverse mode) while
  older pages load around it, for as long as it is on screen. An anchor
  naming an item that is not loaded yet is placed the moment it
  appears, and `onAnchorPlaced` tells you when; an anchor on the newest
  message means "the end" and lets new messages push in; clear the
  anchor when the viewer is back at the end.
* `onEdgeReached` fires when the loaded edge enters the cache window,
  never at open for a history longer than a screen, and once per page
  until that edge gains items (`prependItems([])` after a failed load
  re-arms it).

## A document

```dart
final reader = ReaderController<Paragraph>(
  items: paragraphs,
  idOf: (p) => p.id,
  typeKeyOf: (p) => p.isHeading ? 'heading' : 'body',
  typeConfigs: {
    'heading': const ItemTypeConfig<Paragraph>(
      typeName: 'heading', defaultHeight: 56, defaultConfidence: 0.9,
      widthSensitivity: WidthSensitivity.invariant,
    ),
    'body': ItemTypeConfig<Paragraph>(
      typeName: 'body', defaultHeight: 80,
      estimator: premeasurer.createEstimator<Paragraph>(
        textExtractor: (p) => p.text, style: bodyStyle, padding: bodyPadding,
      ),
    ),
  },
  initialWidth: width,
);

reader.jumpToId('p_25000');                   // builds a screenful, not 25,000 items
await reader.animateToIndex(400, alignment: 0.25);
reader.visibility.value.firstVisible;         // data index, after each frame
```

## How it works

`ReaderView` is a `CustomScrollView` on your `ScrollController` with the
items in one `SliverReaderList`. The sliver lays out every pass from one
**seed** child and expands outward to the cache window:

1. **A jump seeds at the target** at the model's offset and corrects the
   scroll offset to the alignment inside the same layout pass, so a
   jump from item 0 to item 5,000 of 10,000 builds a screenful
   (`test/claims/jump_cost_test.dart`), and a jump requested before the
   first layout waits for it.
2. **A reference child holds its place.** The seed is the pinned anchor,
   else index 0 when the viewport is at the end (follow mode), else the
   first visible child of the previous pass (or its next neighbour when
   it was removed). Layout offsets are remembered by item id, so an
   insert, a removal or a re-measured height before the reference child
   moves nothing on screen (`test/claims/keep_position_test.dart`,
   `anchor_test.dart`).
3. **Drift is settled in-frame.** Layout offsets dead-reckon from the
   seed; when the run reaches index 0 off the origin, the sliver shifts
   the run and the viewport together with a scroll offset correction.
4. **Extents are recorded during layout** (tier 3), so estimates only
   matter for what has never been built. Type defaults (tier 1) and
   estimators (tier 2) seed the model; `MeasurementScheduler`
   pre-measures text in idle frames.
5. **Edges are reported after the frame** with the visible range, and
   the controller fires `onEdgeReached` and updates `visibility`
   (`test/claims/lazy_loading_test.dart`, `visibility_and_width_test.dart`).

In reverse mode a `ReverseLayoutModel` maps layout order to data order;
offset 0 is the newest end and your `scrollController.jumpTo(0)` still
means "latest".

## API

### `ReaderController<T>`

| Member | What it does |
| --- | --- |
| `items`, `idOf`, `typeKeyOf`, `typeConfigs`, `initialWidth`, `bucketSize` | Construction; `typeConfigs` needs every type key (asserted), ids must be unique, `initialWidth` may be left unknown (the first layout sets it) |
| `setItems(list, {hasMoreBefore, hasMoreAfter})` | Diff by id (moves included); resets the loading guard of an edge that gained items; sets the flags when given |
| `appendItems`, `prependItems`, `insertItems`, `removeItems`, `updateItem` | Batch mutations; append / prepend reset their edge's guard, an empty list too |
| `itemCount`, `itemAt(i)`, `indexOfId(id)`, `items` | Data order |
| `jumpToId(id, alignment)`, `jumpToIndex(i, alignment)` | Placed inside the next layout; unknown ids are ignored |
| `animateToId`, `animateToIndex`, `scrollToEnd`, `animateToEnd` | Motion policy is yours (duration, curve) |
| `hasMoreBefore`, `hasMoreAfter`, `onEdgeReached` | Lazy loading, gated on the cache window; a flag set to true re-arms a reached edge |
| `atEndThreshold`, `isAtEnd`, `onAtEndChanged` | "At the end" in pixels |
| `visibility` | `ValueListenable<VisibilityState>` in data order |
| `engine`, `registry` | The pure-Dart engine and registry underneath |

`alignment` is where the item's leading edge lands, as a fraction of the
sliver's paint area from its leading edge: `0` at the edge, `0.5` in the
middle, `0.7` as a chat anchor. In reverse mode the leading edge is the
bottom. The paint area is the viewport less whatever precedes the sliver
on screen, so a leading spacer that scrolls away does not shift the
placement, while a pinned header before the list does (the item lands
below it). A placement is settled over the same frame's layout passes.

### `ReaderView<T>`

`controller`, `scrollController` (required), `itemBuilder(context, index,
item)`, `reverse`, `anchor`, `onAnchorPlaced`, `leadingSlivers`,
`trailingSlivers`, `padding`, `physics`, `scrollCacheExtent`,
`addAutomaticKeepAlives` (off), `addSemanticIndexes` (indices count in
data order in both directions), `itemUpdateListenable` (rebuilds the
visible items when it notifies, for search highlights). With a
`PageStorageKey` as its key, the view remembers the first visible item
and its offset and places it again when rebuilt under that key: the
same content returns even after heights changed.

### `ReaderAnchor(id, alignment)`

The pinned item. Setting a new anchor places it once; the same anchor
again does nothing; `null` releases it without moving anything. The
anchor is the list's reference child only while it is on screen (an
off-screen anchor would move what is being read), never when it is the
item at the origin (that anchor means "the end"), and it is placed again
if its item vanishes and returns.

### Engine (pure Dart)

`ReaderItem<T>`, `ItemTypeConfig<T>` (`defaultHeight`,
`defaultConfidence`, `widthSensitivity`, `estimator`,
`proportionalHeightFn`), `ItemRegistry<T>` (items and heights, id
lookups, batch mutations, width recompute), `ChunkedHeightIndex` (a
Fenwick tree over buckets of heights and one over their jump error),
`FenwickTree`, `ReaderEngine<T>` (jumps, model-offset compensation and
visibility for non-widget hosts), `ScrollCompensator`, `VisibilityState`,
`LoadDirection`.

### Measurement

`TextPremeasurer(textDirection:)` measures text or spans and builds
estimators; `MeasurementScheduler<T>` runs batches after frames and
reports premeasured heights; `MeasuredItem` reports a child's laid-out
height for custom scroll implementations.

### Search

`ReaderSearchController<T>(reader, textExtractors, debounceDuration,
alignment)`: case-insensitive search over the loaded items with
`nextMatch` / `previousMatch` / `jumpToMatch`, counts and per-item
matches; `buildHighlightedSpan` renders matches with the styles you
pass. Strings and widgets are yours.

## Claims and their tests

| Claim | Test |
| --- | --- |
| A jump builds a screenful, lands at the alignment, in both directions, even before the first layout | `test/claims/jump_cost_test.dart` |
| Older pages, live inserts, edits above the viewport, removals and reorders move nothing on screen; at the end a new item pushes in | `test/claims/keep_position_test.dart` |
| An anchor holds through ten pages and new messages, is placed when its item lands, releases without a move | `test/claims/anchor_test.dart` |
| Edge loading never fires at open for a long history, fires once per page, honours the guard; `isAtEnd` follows the threshold | `test/claims/lazy_loading_test.dart` |
| Visibility is the screenful in data order in both directions; a width change reaches the registry and keeps the top item; mutations render without a host rebuild | `test/claims/visibility_and_width_test.dart` |
| `onAnchorPlaced` fires once; an anchor on the newest message means the end; flags travel with `setItems`; an unknown width is set by the first layout; a move near the end or of the reference child, and deleting the reference child, keep the screen; ten heterogeneous pages land without a shift while scrolled up, anchored or at the top; a keyboard-sized viewport change keeps the end or the reference; PageStorage brings each room back, even after heights changed; semantic indices survive diffs; 5,000 items keep a screenful of widgets alive | `test/claims/adoption_asks_test.dart` |
| Inserts inside and just above the visible range, items taller than the viewport, zero-height items, keep-alives, padding, bouncing physics, RTL, rapid jumps, a vanished anchor, an emptied list, a flag flipped on later, animation across unmeasured regions | `test/claims/corner_cases_test.dart` |
| 120 random drags, jumps, inserts, removals, edits and anchors per seed, five seeds per direction: rows tile the screen with no gap, overlap or skipped neighbour; a mutation outside the visible range moves nothing; `scrollToEnd` is flush; the origin is exact afterwards | `test/stress/random_walk_test.dart` |
| `setItems` cost with one edit, one removal, one move at 500 and 5,000 items | `test/stress/set_items_benchmark_test.dart` (`benchmark` tag) |
| The jump error estimate spans buckets through the error tree | `test/engine/jump_error_test.dart` (a `benchmark`-tagged timing) |
| Engine data structures | `test/engine/` |
| Layout models, the diff, the controller, measurement, search | `test/layout/`, `test/controller/`, `test/measurement/`, `test/search/` |
| Files stay under 400 lines (engine 500) | `test/architecture/file_size_test.dart` |

## Numbers

Measured by `flutter test --tags benchmark` on a laptop, in the Dart VM
in debug mode; treat them as ceilings.

| Operation | Cost |
| --- | --- |
| `setItems` over 500 items: unchanged list / one edit / one removal and one append / one move | 209 / 1128 / 828 / 325 µs |
| `setItems` over 5,000 items: unchanged list / one edit / one removal and one append / one move | 2276 / 2330 / 3214 / 3217 µs |
| A jump from item 0 to item 5,000 of 10,000 | under 40 widgets built (`jump_cost_test`) |
| 5,000 items after a jump every 100 and a fling | under 40 widgets alive (`adoption_asks_test`) |
| The engine's jump error estimate over 200,000 items, far versus near | about the same (`jump_error_test`, `benchmark` tag) |

## What it does not do

* Search is a linear scan over loaded items; nothing lazily loaded is
  searched.
* A moved item is re-inserted and re-estimated until it is laid out
  again; everything else keeps its measured height.
* No Material: no search bar, no highlight widget, no strings.
* Semantics traverse in visual order (top to bottom, so oldest first in
  a chat); the package only keeps the "item n of m" indices in data
  order. A pinned header before the list is not accounted for by the
  alignment's frame of reference.

## Development

```sh
fvm flutter analyze
fvm flutter test --exclude-tags benchmark
fvm flutter test --tags benchmark
cd example && fvm flutter run
```

Testing notes for adopters:

* Reach an edge through the controller. `scrollToEnd()` and
  `jumpToIndex(0)` / `jumpToId` land exactly in one frame. A raw
  `scrollController.jumpTo(position.maxScrollExtent)` targets the
  extent as estimated *before* the jump; the far end's real heights
  arrive in that layout, the extent grows, and the viewport snaps to
  the new maximum a frame later, so a test that wants "the far edge
  reached" through the scroll controller must pump until `pixels ==
  maxScrollExtent`. The claim tests use `jumpToIndex` for this reason.
* Layout reports, and with them `visibility`, `onEdgeReached`,
  `onAtEndChanged` and `onAnchorPlaced`, arrive after the frame: pump
  once for the layout and once for the callbacks.
* An offset past the extent (a jump whose target's real heights were
  smaller than estimated) stays there until a gesture ends and the
  physics spring it back, as in any dead-reckoning list; assert scroll
  ranges after `pumpAndSettle`, not after a bare `pump`.
* `test/stress/random_walk_test.dart` is the template for a
  model-based check of your own list: rows must tile, neighbours must
  be consecutive, and nothing visible may move on a mutation outside
  the visible range.

## License

Apache 2.0. The engine (`lib/src/engine/`) was
[dev-altern/reader_engine](https://github.com/dev-altern/reader_engine)
`44ad8b0`, folded in under the same license.
