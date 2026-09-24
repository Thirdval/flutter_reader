# Changelog

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
