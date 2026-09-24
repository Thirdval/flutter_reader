# Changelog

## 2.1.0

Asked for by the Tendvine adoption, and found by a randomized stress
walk over the sliver (`test/stress/`).

### Added

* `ReaderView.onAnchorPlaced(id)`: called after the frame in which the
  anchor landed at its alignment, at once for a loaded item or when a
  later `setItems` brings it. Start a highlight there.
* `ReaderController.setItems(items, {hasMoreBefore, hasMoreAfter})`:
  the edge flags travel with the list. Setting a flag to true re-arms
  the edge callback if that edge is already inside the cache window.
* `ReaderController.initialWidth` is optional (0 = unknown); the first
  layout re-estimates at the real width.
* Content-exact restore: a `ReaderView` under a `PageStorageKey`
  remembers its first visible item and offset and places it again on
  return, so the same content comes back even after heights changed.
* Moves: `setItems` re-inserts only the items that changed relative
  order (a longest increasing subsequence keeps the rest, heights
  included). `ReplaceAll` is gone from `ItemDiffOp`.
* Semantic indices count in data order in both directions.
* `test/stress/random_walk_test.dart`: random drags, jumps, inserts,
  removals, edits and anchors with tiling, neighbour, keep-position and
  origin invariants after every step; `test/claims/adoption_asks_test.dart`
  and `corner_cases_test.dart`; `set_items_benchmark_test.dart`.

### Fixed

* An anchor kept pinning the list while scrolled out of view, so a
  height change between it and the viewport moved what was on screen.
  The anchor is the reference child only while it is visible.
* An anchor set on the newest message (the origin) pinned it once a
  newer message arrived. Such an anchor means "the end": new messages
  push in.
* An anchor whose item vanished was not placed again when it returned.
* A fulfilled jump was replayed by a fresh sliver (a room switch, a
  PageStorage restore).
* A placement clamped at the origin settled at the sliver's start, not
  the viewport's, leaving a leading spacer's height between them.
* `MeasuredItem` and the scheduler aside, `initialWidth: 0` no longer
  scales estimator-less heights by a zero ratio on the first layout.

## 2.0.1

* A placement (a jump or a newly set anchor) is settled against the
  sliver's actual paint area over the same frame's re-layout passes.
  With a leading sliver still on screen (a 4 px spacer at the bottom of
  a chat), the item landed short by that sliver's visible extent.
* README: the alignment's frame of reference, and a testing note on
  `jumpTo(maxScrollExtent)` versus `scrollToEnd` / `jumpToIndex`.

## 2.0.0

A rewrite of the widget layer around an engine-backed sliver, with the
engine folded in. Breaking throughout; the pure-Dart engine API is the
same shape with generics added.

### Added

* `SliverReaderList` / `RenderSliverReaderList`: a sliver that lays out
  from the engine model. A jump seeds layout at the target item and
  builds only the viewport and its cache window. One reference child
  (the anchor, the first visible child, or index 0 at the end of the
  list) keeps its place while items are inserted, removed or
  re-measured around it; drift between layout and model offsets is
  settled with an in-frame scroll offset correction.
* `ReaderView.scrollController` (required): the host owns the scroll
  controller. `reverse` mode puts the last item at offset 0.
* `ReaderAnchor`: an item kept pinned at an alignment while pages load;
  placed as soon as the item is loaded.
* `ReaderView.leadingSlivers` / `trailingSlivers`.
* `ReaderController.setItems`: an id-based diff (removals, insertions,
  payload refresh; a reorder rebuilds) for hosts that render a watched
  list.
* `ReaderController.atEndThreshold`, `isAtEnd`, `onAtEndChanged`.
* Edge loading (`onEdgeReached`) fires after the frame when the loaded
  edge enters the cache window, once per page, never at open for a
  history longer than a screen.
* `ReaderController.visibility` as a `ValueListenable<VisibilityState>`
  in data order, updated after each frame.
* `ReaderController.scrollToEnd`, `animateToEnd`, `animateToIndex`.
* Generic items: `ReaderItem<T>`, `ItemTypeConfig<T>`,
  `ItemRegistry<T>`, `ReaderEngine<T>`, `ReaderController<T>`,
  `ReaderView<T>` with `idOf` / `typeKeyOf` selectors; no `dynamic`.
* `ItemRegistry.setItem`, `reportEstimatedHeight`, `idAt`, `containsId`.
* `TextPremeasurer(textDirection:)`.
* A per-bucket error tree: `ChunkedHeightIndex.estimatedJumpError` costs
  O(B + log(N/B)) instead of a walk over every item between the ends.
* `test/claims/`: a test per README claim.
* `example/`: a 10,000-paragraph document and a chat with paging, live
  inserts, edits and anchored jumps.

### Changed

* `reader_engine` is part of this package (`lib/src/engine/`, from
  dev-altern/reader_engine `44ad8b0`); the Flutter import it carried is
  gone.
* `ReaderView.itemBuilder` receives `(context, index, item)` with the
  typed item, not a `ReaderItem`.
* `ReaderView` no longer measures through a post-frame `MeasuredItem`;
  extents are recorded during layout. `MeasuredItem` stays as a helper
  for custom scroll implementations and resets its last report when its
  `itemIndex` changes.
* `MeasurementScheduler` reports premeasured (tier 2) heights, not
  measured ones.
* `ReaderSearchController` takes typed extractors and an `alignment`,
  and exposes counts only; `buildHighlightedSpan` takes the highlight
  styles from the host.
* A missing `ItemTypeConfig` or a duplicate id is an assertion.
* Dart `^3.13.0`, Flutter `>=3.47.0`; Tendvine's lint set; primary
  constructors throughout.

### Removed

* `ReaderSearchBar`, `SearchHighlightText` (Material widgets with
  English strings), `VisibilityNotifier`, `AnchorTracker`,
  `ReaderController.evictDistantItems`, `effectiveTotalHeight`,
  `loadMoreBufferExtent`, `edgeThreshold`, `cacheExtent`.

## 1.0.0

Initial release (dev-altern/flutter_reader).
