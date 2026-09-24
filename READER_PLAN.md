# flutter_reader — Plan of Record (DRAFT, awaiting validation)

The vendored reader package (`frontend/flutter_reader/`, from
github.com/dev-altern/flutter_reader v1.0.0) and its engine
(dev-altern/reader_engine, git `main` @ `44ad8b0`), assessed against
what Tendvine's chat feed, thread page, home timeline and long-form
content need — and the plan that turns it into the list Tendvine runs
on.

**Status:** accepted by the owner 2026-09-24 ("yes go ahead"); P0–P2
built the same day in this folder, published as
`github.com/Thirdval/flutter_reader` v2.0.0 (RD1 settled as an own
public repo, consumed by Tendvine through a git `ref`). P3–P4 are the
"App" session's, against that tag. The assessment below is as written
before the work; §5 tracks what shipped. Written from a full read of both packages (about
1,900 lib lines each, 94 widget-layer tests plus the engine's four
suites), of the four Tendvine surfaces in §1.5, and of an eleven-probe
run against the pinned SDK (appendix A, reproducible in ten minutes).
Every RD-decision in §3 is open until the owner accepts it; progress
is tracked in §5, one row per phase, with an owner check-off after
each phase.

**Predecessors (binding, not restated):** `chat_feature_plan.md`
§3.2 / §3.9 / C3 / C8 (the conversation body as built, the jump with
its 10-page cap, the Pixel findings), `presentation_standard.md`
(page · body · view, states registries, size caps), `CLAUDE.md`
(framework-first rule, design system, lints), `widgetbook_plan.md`.

**Standing rules (owner):** everything stays local (no push, no
remote operation), English only, no goldens recorded — `.states.dart`
registries are still written and catalogued.

---

## 0. Summary for the owner

The engine is real; the widget over it is a prototype. The
Fenwick-tree height index, the bucketed registry and the batch
mutations are correct and tested. Everything the README promises
*above* that layer fails when measured: a jump from message 0 to
message 5,000 builds 5,000 widgets (the sliver is never seeded at the
target), "zero-jank" compensation runs one frame late and moves the
view by the wrong amount, reverse (chat) mode computes visibility from
the wrong end and therefore pages history on every scroll tick, loses
its place when older pages arrive, and ignores the id you asked it to
jump to. The view does not even rebuild when its own controller adds
items. Nothing in the package today would replace the anchor code in
`ConversationBody`; used as is, it would regress the Pixel-verified
feed.

The fix is not a patch list. The package lacks the one piece that
makes its engine matter: **a sliver that lays out from the engine**
(seeded at the engine's index and offset for any scroll position,
keeping one reference child fixed in-frame while items change around
it, and gating edge loads on the cache extent). With that sliver, the
README's claims become true in both directions, and the chat contract
(`ConversationBody`'s props, unchanged) maps onto it directly:
external scroll controller, anchor at 0.7 while the cubit pages, at-
bottom threshold, position kept on live inserts, loader gated.

Plan: **P0** hygiene (vendor into the repo, fold the engine in, fvm
pin, Tendvine's lints, dead widgets out) → **P1** engine truths (a
test per README claim, the controller-level fixes that make the
existing design honest) → **P2** the chat contract (the engine-backed
sliver, generic items, the `setItems` diff, anchor + end semantics)
→ **P3** adoption behind `ConversationBody`'s existing props, then
optionally `ThreadBody` → **P4** delete the hand-rolled anchor code.
The home timeline is out of scope (nothing to gain); long-form
content waits for a surface. Fourteen decisions in §3, all with a
recommendation.

---

## 1. Assessment

### 1.1 Baseline (2026-09-24, Flutter 3.47.1 · Dart 3.13.1)

| Check | Result |
| --- | --- |
| `flutter pub get` | OK; `reader_engine` resolves from git (`main`, resolved `44ad8b0e`, 3 commits, v1.0.0) |
| `flutter analyze` | 1 warning: a publishable package with a git dependency (needs `publish_to: none`); 1 deprecation: `cacheExtent` → `scrollCacheExtent` (`reader_view.dart:211`) |
| `flutter test` | 94 passed (widget layer); 91 passed in the engine (run from a copy of the git checkout) |
| SDK pin | none (`fvm flutter` fails: no `.fvmrc`); the package SDK floor is `^3.9.2`, the app's is `^3.13.0` |
| Repository | git removed this morning; the folder sits **outside** Tendvine's git root (`frontend/tendvine`), so Tendvine's CI (which checks out that root and reads `.fvmrc` there) cannot see it |
| Leftovers | `build/` present (ignored), `.fvm/` not in `.gitignore` |

### 1.2 What is in the box

Two layers, 3.5K lib lines, no shared code with Tendvine yet (the app
does not depend on either package).

**reader_engine** (1,875 lib lines, 4 test files): `FenwickTree`
(159), `ChunkedHeightIndex` + `Bucket` (856, struct-of-arrays
buckets of 128 with a Fenwick tree over bucket totals), `ItemRegistry`
(363, id → bucket map, batch insert/remove, width recompute by
sensitivity), `ReaderEngine` (278, visibility, jump, measurement,
compensation), `ScrollCompensator` (68), three model files. Not pure
Dart despite the README: `item_registry.dart` imports
`package:flutter/foundation.dart` for `debugPrint`.

**flutter_reader** (1,886 lib lines, 7 test files): `ReaderView`
(258, a `CustomScrollView` + one `SliverList` with a delegate whose
`estimateMaxScrollOffset` returns the engine total), `ReaderController`
(454, owns the engine, navigation, lazy-loading state, eviction),
`MeasuredItem` (61), `AnchorTracker` (99), `VisibilityNotifier` (75),
`TextPremeasurer` (152), `MeasurementScheduler` (157),
`ReaderSearchController` (271), `ReaderSearchBar` (207, Material),
`SearchHighlightText` (132, Material).

### 1.3 README claims against the code

Each claim was read in the source and, where it could be, measured
with a probe (appendix A; `P*` below). Thirteen claims: four hold, two
hold in part, seven fail.

| # | Claim (README) | Verdict | Evidence |
| --- | --- | --- | --- |
| C1 | O(log N) jump to any item, from frame 1 | **Refuted at the widget layer** | The engine computes the *offset* in O(log N); the stock `SliverList` then lays out every child between the last attached child and the target because nothing seeds it there. **P1:** jumping from item 0 to item 5,000 of 10,000 built 5,000 widgets. In the engine, `jumpToId` is O(distance) too: `estimatedJumpError` walks every item up to the target (**P11:** 236 µs far vs 5.6 µs near on 200K items; the README says < 0.3 µs). |
| C2 | Zero-jank scroll compensation | **Refuted** | Compensation is a `ScrollController.jumpTo` in a post-frame callback — one frame *after* Flutter laid the item out with its real size. The frame the user saw was right; the "compensation" moves it. **P8:** a forward prepend of 10 items with real heights of 30/90 px against a 50 px estimate moved the top item from #12 to #20. **P5:** in reverse mode a prepend (loading older) moved the view by a whole page (500 → 1,500 px, top #78 → #58): `prependItems` applies compensation without the reverse guard the other mutations have (`reader_controller.dart:321`). |
| C3 | Reverse mode "for chat-style bottom-pinned scrolling" | **Not usable** | (a) Visibility is computed from the raw reversed offset as if it were top-down: at the bottom the engine reports items 0–12 visible while 88–99 are on screen (**P2**). (b) Edge detection therefore fires from the wrong end and re-fires on every scroll tick: one page at open with no scroll, two more after a 30 px drag, and the view jumped 1,000 px (**P3**) — the family of the Pixel finding "paged the whole history on open". (c) `jumpToId` / `animateToId` ignore the id and go to offset 0; `alignment` is ignored (**P6**: item_5 requested, view at the bottom, item not on screen). (d) `didUpdateWidget` swaps controllers with "no anchor tracking needed — just swap" (`reader_view.dart:114`): true only because nothing is tracked in reverse. (e) `isAtEnd` is a 1 px test; Tendvine's contract is 48 px; there is no change callback. (f) `evictDistantItems` centres its window on the wrong visibility and applies head compensation unguarded (`:403`). No test mentions reverse. |
| C4 | Lazy loading with edge detection and loading guards | **Partly** | The guards work and are tested. Detection is an item-count threshold on engine visibility: right in forward mode, wrong in reverse (C3). There is no cache-extent gate; the callback fires from visibility, which is acceptable once visibility is right. The documented "initial edge check" fires `before` at open whenever `hasMoreBefore` — in a chat that is "load older on open", which the feed must not do. |
| C5 | Batch mutations "notify listeners" and appear | **Refuted for the widget** | `ReaderView` never listens to its controller. **P4:** after `appendItems(5)` the controller reports 15 items, the list still renders 10. Every README example, the chat one included, only works if the host calls `setState`. |
| C6 | "ReaderView detects viewport width changes automatically" | **Refuted** | The view watches `viewportDimension` (height) only; `onWidthChanged` has no caller in the widget layer. **P7:** after 800 → 300 px the registry still reports 800. `TextPremeasurer` hardcodes LTR. |
| C7 | Accurate scroll extent from frame 1 | **Confirmed** | `_ReaderChildDelegate.estimateMaxScrollOffset` returns the engine total (clamped by commit `6b418c7`). In reverse the `loadMoreBufferExtent` is added at the *newest* end, where a chat never loads. |
| C8 | Three-tier measurement; `MeasuredItem` reports ground truth | **Confirmed, with a caveat** | Post-frame reporting is correct and the index flip in reverse is right. The render object caches `_lastReportedHeight` per *slot*, not per item: after an insert shifts indices, a slot whose new item happens to share the old height never reports, so the engine keeps that item's estimate. |
| C9 | Full-text search with match navigation | **Confirmed, narrow** | A linear case-insensitive scan of *loaded* items only (`engine.itemCount`); nothing lazily loaded is searched. Jumps at alignment 0.3 (the README recommends 0.5). English baked in (`'No results'`, `'3 of 17'`, `'Search…'`). `ReaderSearchBar` and `SearchHighlightText` are raw Material (`Icons.*`, `Colors.yellow` / `Colors.orange`, `Theme.of(context).colorScheme`): unusable in Tendvine as they are (`solar_icons_only_test`, petrol & zand conventions). |
| C10 | Windowed eviction | **Confirmed in forward mode**, wrong in reverse | Tested forward (6 tests). Wrong window and unguarded compensation in reverse (C3f). Not applicable to Tendvine: the feed is a DAO watch and the cubit owns the window; the list must render what it is given. |
| C11 | "Test coverage: 94 tests" with a per-group table | **Count right, table wrong** | The table lists 4 `ReaderSearchBar`, 4 `SearchHighlightText`, 13 `ReaderView` and 9 `AnchorTracker` tests; there are 0, 0, 5 (+ 2 `MeasuredItem`) and 6 (appendix B). No test covers reverse mode, a jump's cost, keeping position, a width change through the widget, or `jumpToId` before layout (**P10:** a null-check throw; the README's "don't"). |
| C12 | "`reader_engine` — pure Dart, no Flutter imports" | **Refuted** | `foundation.dart` for `debugPrint`; the pubspec depends on the Flutter SDK. |
| C13 | Performance table (31K items: build ~1 ms, jump < 0.3 µs, "every operation < 0.003 % of a frame") | **Unverifiable; jump figure contradicted** | No benchmark exists in either repository (the engine's benchmark placeholder was removed in `acfd2b7`). P11 measures the far jump at 236 µs. |

### 1.4 Sound parts, worth keeping

- **`ChunkedHeightIndex` + `FenwickTree`**: correct and tested
  (1,000-item offset round trip, split and merge, bulk rebuild, 10K
  Fenwick correctness); offsets in O(B + log(N/B)), cache-friendly.
- **`ItemRegistry`**: id → bucket map (appends O(1)), batch
  insert/remove with a rebuild past the bucket size, width recompute
  by sensitivity with a viewport-first pass.
- **`ReaderEngine`**: the mutation and compensation arithmetic is
  right *for a forward list whose scroll offset is the engine's
  offset*; the reverse defects are all in the widget layer feeding it
  the wrong offset.
- **`MeasuredItem`**, **`TextPremeasurer`**, **`MeasurementScheduler`**:
  fine for long-form content (idle-frame batches, one reused
  `TextPainter`).
- **The `estimateMaxScrollOffset` delegate**: the one line that
  already makes Flutter use the engine.
- **`ReaderSearchController`'s matching**: keep the logic, not its
  widgets.

### 1.5 Against the Tendvine surfaces

#### 1.5.1 `ConversationBody` (the chat feed)

`presentation/conversation/views/conversation_body/conversation_body.dart`
(345 lines): a reversed `CustomScrollView` pinned to the bottom, the
page's `ScrollController` (`conversation_page.dart` jumps to 0 for
"latest", `PageStorageKey` per room), at-bottom by a 48 px threshold
(drives mark-read and "new below"), a jump target anchored at 0.7 via
`center:` while `JumpPaging` (cubit, cap 10 pages) loads older until
the target lands, older pages prepended with the position kept, a
history loader gated by `SliverLayoutBuilder.remainingCacheExtent`
(the Pixel finding), day and NEW dividers as entries, typing caption
and composer outside the list, reduced-motion aware `animateTo`
through `MotionScale.shouldAnimate`.

| Requirement | Reader today | Gap → phase |
| --- | --- | --- |
| Reverse list pinned to the bottom | `reverse: true` exists, broken (C3) | P1 mapping, P2 sliver |
| The page owns the `ScrollController` (`jumpTo(0)` = latest, `PageStorageKey` per room) | `ReaderView` creates and disposes its own; none accepted | P2 (RD4) |
| At-bottom by a 48 px threshold → `onAtBottomChanged` | `isAtEnd` at 1 px, no callback | P2 (RD7) |
| Jump target anchored at 0.7 while older pages load until it lands (cap 10) | `jumpToId` ignores the id in reverse; no anchor notion; an id not yet loaded cannot be expressed | P2 (`anchor`, RD7) |
| Older pages prepend with the position kept | Free in a reversed single sliver only if nothing compensates; the reader compensates and jumps a page (P5) | P1 guard, P2 in-frame |
| History loader fires only when the top enters the cache extent | Fires at open and per scroll tick (P3) | P1 (correct visibility), P2 (cache-extent gate in the sliver) |
| Live edits, deletes and inserts keep the position | An insert at the newest end shifts the content by one item (P9); an unkeyed reversed sliver cannot do better — the current body has the same trait (not probed in the app) | P2 (reference-child rule) |
| Day and NEW dividers inside the list | Fine: entries with their own `typeKey` and stable synthetic ids; `buildConversationEntries` already produces them | P3 |
| Typing caption, composer, status strips outside the list; keyboard inset owned by the composer | Unaffected | — |
| Reduced-motion `animateTo` | `animateToId` takes duration and curve; the motion policy stays in the page | — |
| `addAutomaticKeepAlives: false`, one `RepaintBoundary` per item | Delegate defaults: keep-alives on, a second `RepaintBoundary` inside `MeasuredItem` | P2 |
| Typed items (`Message`, `MessageId`; lints `no_dynamic_casts`, `no_raw_types`) | `ReaderItem.data` is `dynamic`; the builder gets `(context, index, ReaderItem)` | P2 (RD5) |
| Bubble semantics and order | `addSemanticIndexes` on; reverse yields newest-first, as today | P3 verification |
| RTL | The viewport is direction-agnostic; `TextPremeasurer` LTR only | P1 |

#### 1.5.2 `ThreadBody`

A forward `ListView.builder`: root, "n replies" divider, replies
oldest first, `LoadMoreFooter` at the end (fires from its own
`initState`, so only when built), an optional page-owned controller,
no jump. The reader's forward mode renders it today (C7, C8) but adds
nothing until a thread needs a jump (a `thread.reply` push landing on
its reply) or grows long. Adoption value: low. It is the cheapest
forward-mode proof and stays optional (P3b).

#### 1.5.3 `ChatHomeBody` (the home timeline)

A sectioned `CustomScrollView`: jump bar, catch-up strip, collapsible
section headers, `SliverList.builder` rows, footer rows, bottom
clearance. Dozens of rows, no paging, no jump, no measurement
concern. A single-sliver reader does not fit and would bring nothing;
flattening sections into typed items would trade a clear sliver
composition for a model with no benefit. **Out of scope (RD9).** A
timeline the owner names later qualifies when it is long (hundreds of
rows and more), paged, or jump-targeted from notifications.

#### 1.5.4 Long-form reader content

No Tendvine surface exists today. Forward mode with the measurement
pipeline is the package's original case and mostly works (C7, C8);
C1, C2, C5 and C6 apply to it as well and are fixed by P1/P2 for both
directions. Adoption waits for a surface (RD10).

### 1.6 Hygiene

- `pubspec.yaml`: git dependency without `publish_to: none`; SDK
  `^3.9.2` against the app's `^3.13.0`; no `.fvmrc`; `.fvm/` not
  ignored; a stale `build/`.
- `cacheExtent` deprecated on this SDK (`reader_view.dart:211`).
- Lints: `flutter_lints` only. Tendvine's `analysis_options.yaml`
  (primary constructors, `prefer_single_quotes`,
  `always_declare_return_types`, `discarded_futures`,
  `unawaited_futures`, `no_dynamic_casts`, `no_raw_types`,
  `sort_constructors_first`, `prefer_final_locals`) is not applied;
  every class uses a classic constructor; `dynamic` is pervasive
  (`ReaderItem.data`, every extractor and estimator signature).
- Size caps: `reader_controller.dart` 454 (> 400),
  `chunked_height_index.dart` 856 (> 500).
- `notifyListeners()` on every scroll event
  (`reader_controller.dart:422`): any `ListenableBuilder` on the
  controller rebuilds per frame while scrolling.
- `attach()` schedules two nested post-frame callbacks and never
  cancels them; `detach()` only nulls the controller.
- No `print`; two `debugPrint` calls inside `assert` — fine.
- English strings in the search controller's display and bar.
- The README documents parameters that do not exist in its own table
  (`reverse` is missing from the `ReaderView` table) and a test
  breakdown that is fiction (C11).

---

## 2. Target: what the package becomes

### 2.1 Shape

One package at `packages/flutter_reader` inside the Tendvine repo
(RD1), the engine folded in as `lib/src/engine/` (RD2), four layers:

- **engine** (pure Dart): the algorithms unchanged; `estimatedJumpError`
  skips whole buckets; typed `ReaderItem<T>`; duplicate ids asserted;
  the Flutter import gone.
- **sliver** — `SliverReaderList`, the missing piece (RD3): a
  `RenderSliverMultiBoxAdaptor` that
  1. **seeds** layout at the engine's index and offset for the current
     scroll offset (`addInitialChild(index:, layoutOffset:)`, the hook
     `SliverFixedExtentList` uses) instead of walking from index 0, so
     a jump builds only the viewport plus the cache window;
  2. **measures during layout**: each child's laid-out extent goes to
     the engine in the same `performLayout` (Tier 3 without a
     post-frame round trip);
  3. **keeps one reference child fixed** across a layout pass — the
     anchor item when one is set, otherwise the first attached child,
     except in follow mode (at the end within the threshold): inserts,
     removes and height deltas *before* the reference child become an
     in-frame `scrollOffsetCorrection`, and both signs of estimate
     error near index 0 are absorbed without moving the content (the
     stock sliver snaps to the top on a positive gap);
  4. **gates edge loading** on `constraints.remainingCacheExtent` at
     the loaded edge, once per page, never at open unless the edge is
     inside the cache window;
  5. is **keyed by id** (`findChildIndexCallback` through the engine's
     id map) so a shift of indices re-associates elements instead of
     re-purposing slots;
  6. handles reverse through the viewport plus a small `ReverseMapping`
     (raw ↔ engine index and offset, unit-tested); offset 0 stays the
     newest end.
- **controller** — `ReaderController<T>`: items, engine, lazy-loading
  state; attaches to the position it is given, never owns a
  `ScrollController` (RD4). Navigation: `jumpToId(alignment)`,
  `animateToId(duration, curve)` (motion policy stays in the host),
  `scrollToEnd()`, `isAtEnd`, `onAtEndChanged` with `atEndThreshold`
  (RD7), `visibility` as a `ValueListenable` (no per-tick
  `notifyListeners`). Mutations: `setItems(List<T>)` with an id diff
  (RD6) plus `append`/`prepend`/`insert`/`remove`.
- **view** — `ReaderView<T>`: `CustomScrollView(controller: the host's,
  reverse:, scrollCacheExtent:, physics:, slivers: [...leading,
  SliverReaderList, ...trailing])` with `leadingSlivers` and
  `trailingSlivers` slots so the body's spacer and the history loader
  stay slivers; the view rebuilds on controller changes itself.
- **search**: `ReaderSearchController<T>` kept with typed extractors
  and a pure `highlightSpans(text, matches, style)` helper;
  `ReaderSearchBar` and `SearchHighlightText` leave the package (RD8).
- **long-form helpers**: `MeasuredItem`, `TextPremeasurer`
  (`textDirection` parameter), `MeasurementScheduler` unchanged
  beyond lints (RD13).

### 2.2 The chat contract (what `ConversationBody` will call)

Indicative, to be frozen at the end of P2:

```dart
final reader = ReaderController<ConversationEntry>(
  items: entries,                       // oldest first, as the cubit hands them
  idOf: (e) => e.key,                   // 'm-<id>' | 'day-<yyyy-mm-dd>' | 'new'
  typeKeyOf: (e) => e.typeKey,          // 'message' | 'day' | 'new'
  typeConfigs: conversationTypeConfigs, // estimates per type, invariant dividers
  initialWidth: width,
  hasMoreBefore: hasOlder,              // the older end is engine index 0
  onEdgeReached: (_) => actions.onLoadOlder(),
  atEndThreshold: 48,
  onAtEndChanged: actions.onAtBottomChanged,
);

ReaderView<ConversationEntry>(
  controller: reader,
  scrollController: widget.scrollController,      // page-owned, PageStorageKey per room
  reverse: true,
  anchor: jumpTarget == null
      ? null
      : ReaderAnchor(id: 'm-${jumpTarget.value}', alignment: 0.7),
  leadingSlivers: [SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xs.value))],
  trailingSlivers: [SliverToBoxAdapter(child: _top(context, l10n))],  // loader or intro
  itemBuilder: (context, entry) => _entry(context, entry),
);
```

Semantics:

- **`setItems`** on every cubit emission; the reader diffs by id
  (insert, remove, move as remove + insert) and applies the
  reference-child rule, so live edits, deletes and inserts never move
  what the viewer is reading.
- **`anchor`** pins the named item's leading edge at `alignment`
  while everything else changes; it may name an item that is not
  loaded yet — the cubit keeps paging (`JumpPaging`, unchanged) and
  the reader pins the moment `setItems` brings the id; the page
  clears it when the viewer is back at the end (`clearJump`, as
  today), and `scrollController.jumpTo(0)` remains "latest".
- **Follow mode**: at the end (within `atEndThreshold`) a new item
  simply takes offset 0; scrolled up, it is compensated in-frame and
  the cubit's `newBelow` count works as today.
- **Edge loading** fires once per page when the loaded older edge
  enters the cache window; `hasMoreBefore` from `hasOlder`; the
  trailing loader sliver renders `LoadMoreFooter` exactly as now
  (status, retry, end label) without its own gate.

### 2.3 What stays in Tendvine, unchanged

`ConversationBodyActions`, `conversation_body.states.dart`,
`buildConversationEntries`, `conversation_page.dart` (its
`ScrollController`, `_jumpToLatest` with the reduced-motion branch),
`JumpPaging` and `ConversationCubit.jumpTo`, `ConversationState`, the
composer, the day / NEW entries, the intro and loader row, all copy.

---

## 3. Decisions to validate (RD)

| # | Decision | Recommendation | Alternative |
| --- | --- | --- | --- |
| RD1 | Where the package lives | ~~Vendor into the Tendvine repo~~ **Settled by the owner: an own public repo, `github.com/Thirdval/flutter_reader`, consumed through a git dependency pinned by tag** (`ref: v2.0.0`). The sibling folder is that repo's working tree | vendor into `packages/flutter_reader` (rejected: the owner wants it reusable from the org) |
| RD2 | The engine | **Fold `reader_engine` into the package** (`lib/src/engine/`, its tests along, the Flutter import dropped, the public API re-exported as today; `CHANGELOG` records the source commit `44ad8b0`) | a second vendored package `packages/reader_engine`; keep the git dependency pinned to `ref: 44ad8b0e…` (drift from `main` is invisible until an upgrade) |
| RD3 | The list mechanism | **An engine-backed sliver, `SliverReaderList`** (§2.1): seeded layout, in-frame corrections, cache-extent gate, keyed by id. It is what makes C1, C2, C3, C5 true | (a) keep the stock `SliverList` and move Tendvine's `center:` three-sliver anchoring into the package — proven, but the engine stays decorative and live inserts still shift; (b) a third-party list (`super_sliver_list`, `scrollable_positioned_list`) — rejected, the owner wants this package |
| RD4 | Scroll controller ownership | **The host passes its `ScrollController`** (required); the reader attaches to the position | a reader-owned controller exposed through a getter (the page's `PageStorageKey` and `_jumpToLatest` would move) |
| RD5 | Item typing | **Generic `ReaderItem<T>`, `ReaderController<T>`, `ReaderView<T>`** with `idOf` / `typeKeyOf` selectors; the builder receives `T`; no `dynamic` anywhere (`no_dynamic_casts`, `no_raw_types`) | keep `ReaderItem(id, typeKey, data: Object?)` and cast at every call site |
| RD6 | Feed model | **`setItems(List<T>)` with an id diff** as the primary mutation (the cubit hands the whole watched list); `append` / `prepend` / `insert` / `remove` kept for imperative hosts | append / prepend only (the body would diff itself) |
| RD7 | Anchor and end semantics | **`anchor: ReaderAnchor(id, alignment)`**, `atEndThreshold`, `onAtEndChanged`, `isAtEnd`; offset 0 stays the newest end in reverse | anchor by index; end detection left to the host's scroll listener (as today) |
| RD8 | Search widgets | **Drop `ReaderSearchBar` and `SearchHighlightText`** (raw Material, English strings); keep the controller and a span helper; Tendvine keeps its own search UI (C5's splitter) | wrap them behind design-system components (work for a UI Tendvine does not need) |
| RD9 | Home timeline | **Out of scope; `ChatHomeBody` unchanged** | flatten sections into reader items (no gain) |
| RD10 | Long-form content | **No adoption until a surface exists**; forward mode stays covered by the claims suite so the package remains general; the `example/` app (P2) is the review surface | a widgetbook demo page in the app (review value only) |
| RD11 | Lints and caps | **Adopt Tendvine's `analysis_options.yaml` and the 400 / 500 caps** through a package-local ledger test; primary-constructor migration in P0 (mechanical) | `flutter_lints` only |
| RD12 | Eviction | **Remove `evictDistantItems`** (the host owns the window; a DAO-watch feed never needs it) | keep, fix for reverse, test |
| RD13 | Measurement helpers | **Keep** `MeasuredItem`, `TextPremeasurer`, `MeasurementScheduler` as forward-mode helpers, lints plus a `textDirection` parameter only | remove until a long-form surface exists |
| RD14 | README | **Rewrite from the tests**: every claim names the test that proves it; the comparison and performance tables go (unverified numbers) | keep with corrections |

---

## 4. Phases

### 4.0 Standing rules for every phase

- **Local only.** No push, no remote operation; commits only when the
  owner asks. English only. No goldens recorded; `.states.dart`
  registries are still added and catalogued (`widgetbook/catalog.dart`).
- **A test before every fix.** Each README claim gets a test named
  after it; the appendix A probes are the seed. A fix lands with the
  test that was red before it.
- **Both suites green before a phase closes:** `fvm flutter analyze`
  and `fvm flutter test` in `packages/flutter_reader` and in the app;
  Tendvine's convention tests unchanged (`view_conventions_test`,
  `layer_imports_test`, `solar_icons_only_test`, size ledger,
  catalogue coverage).
- **Size caps** in both trees: presentation ≤ 400 lines, data ≤ 500.
- **Owner check after each phase**; on the Pixel from P2 on. A phase
  is ✔ only after the owner ran it.
- Sizes: S = a session, M = a few sessions, L = a week of focused
  work.

### P0 — Hygiene (S)

Deliverables:

- [x] Move `frontend/flutter_reader` → `frontend/tendvine/packages/flutter_reader`
      (RD1); `flutter_reader: path: packages/flutter_reader` in the
      app's `pubspec.yaml`; `.fvmrc`
      `{"flutter": "3.47.1"}` in the
      package and `.fvm/` in its `.gitignore`; `publish_to: none`;
      SDK `^3.13.0`; `build/` deleted; upstream URL kept in `CHANGELOG`.
- [x] Fold the engine in (RD2): `lib/src/engine/{core,model,registry,
      scroll,engine}`, tests under `test/engine/`, the
      `foundation.dart` import replaced (`assert`-only logging),
      `CHANGELOG` names commit `44ad8b0` of dev-altern/reader_engine.
- [x] `cacheExtent` → `scrollCacheExtent`; analyze clean.
- [x] Tendvine's `analysis_options.yaml` copied in (RD11): primary
      constructors, single quotes, declared return types,
      `discarded_futures`; gratuitous `dynamic` removed where a type
      exists (the generic item lands in P2).
- [x] Package-local size ledger test; `Bucket` into `bucket.dart`
      (856 → two files under 500); `reader_controller.dart` split into
      navigation and lazy loading (454 → two files under 400).
- [x] `ReaderSearchBar`, `SearchHighlightText` removed (RD8);
      `evictDistantItems` removed (RD12); `AnchorTracker` removed (dead:
      only used for the controller swap in forward mode, which P2
      handles through the sliver).
- [x] `Makefile` `analyze` / `test` and `ci.yml`'s analyze and unit
      jobs run the package too (`working-directory:
      packages/flutter_reader`, the same `.fvmrc`).
- [x] README trimmed to what exists (the rewrite is P2).

Exit: the package's tests and the engine's tests pass under the app's
SDK and lints. (Done as an own repo instead of a path dependency, per
the owner: `Makefile` / `ci.yml` of the app are untouched; the package
has its own workflow.)

Owner check: a look at the tree and the CI mirror; nothing to run.

### P1 — Engine truths (M)

Deliverables (a test per claim, `test/claims/<claim>_test.dart`, the
probe becomes the first case of each):

- [x] `ReverseMapping` (raw ↔ engine index and offset) with a
      hand-computed table; `visibility` reports the items actually on
      screen in reverse at offsets 0 and 500 (red today: P2).
- [x] Edge detection uses the mapped visibility: in a reversed 100-item
      list with `hasMoreBefore`, nothing fires at open and one page
      fires when the oldest loaded item enters the threshold, once
      (red today: P3).
- [x] `prependItems` and every mutation keep the reverse guard; a
      reverse prepend of 20 leaves `pixels` and the top item unchanged
      (red today: P5).
- [x] `ReaderView` listens to its controller: `appendItems(5)` renders
      15 items after one pump (red today: P4); scroll state moves to a
      `ValueNotifier<VisibilityState>` so `notifyListeners` no longer
      fires per tick.
- [x] Width detection through `LayoutBuilder` constraints →
      `onWidthChanged` in both directions; `TextPremeasurer(textDirection:)`
      (red today: P7).
- [x] `jumpToId` / `animateToId` honour the id and the alignment in
      reverse through the mapping (red today: P6); still O(distance)
      builds until P2, stated in the doc comment.
- [x] A jump before attach is deferred to the first layout instead of
      throwing (red today: P10).
- [x] Engine: `estimatedJumpError` skips buckets before `from`
      (visited-count test plus a `benchmark`-tagged timing);
      `ItemRegistry.build` / `insertAll` assert unique ids.
- [x] `MeasuredItem` keys its last report by item id, not slot (C8).
- [x] Claims that need the sliver (jump cost P1, non-uniform prepend
      P8, live insert P9) are written now, tagged `pending`, excluded
      from CI like `benchmark` until P2 turns them green.
- [x] README's claims table replaced by the test list (RD14, first
      pass).

Exit: every appendix A probe is a green test (P1, P8 and P9 went green
with P2's sliver in the same day, so nothing was tagged `pending`).

Owner check: read the claims list; optional.

### P2 — The chat contract (L)

Deliverables:

- [x] `SliverReaderList` render object and widget (RD3, §2.1): seeded
      layout at the engine's index and offset; Tier-3 measurement
      inside `performLayout`; the reference-child rule (anchor →
      first attached child → follow at the end); in-frame
      `scrollOffsetCorrection` for inserts, removes and height deltas
      before the reference child, both signs of estimate error near
      index 0 absorbed; `remainingCacheExtent` edge gate; children
      keyed by id; a source note naming the Flutter revision whose
      `RenderSliverList.performLayout` it was derived from.
- [x] `ReaderView<T>`: `scrollController` required (RD4), `reverse`,
      `anchor` (RD7), `leadingSlivers` / `trailingSlivers`,
      `scrollCacheExtent`, `physics`; keep-alives off; one
      `RepaintBoundary` per item.
- [x] `ReaderController<T>` (RD5, RD6): `setItems` with the id diff,
      `hasMoreBefore` / `hasMoreAfter`, `onEdgeReached`,
      `atEndThreshold`, `onAtEndChanged`, `isAtEnd`, `visibility`,
      `jumpToId(alignment)`, `animateToId(duration, curve)`,
      `scrollToEnd()`, `anchor` / `clearAnchor`.
- [x] Claims turn green: jump cost (0 → 5,000 of 10,000 builds only
      the viewport and cache window), forward and reverse prepend with
      30 / 90 px real heights against 50 px estimates, a live insert at
      the newest end while scrolled up, an anchor that survives ten
      prepends of 50 estimated-vs-real items at 0.7, an edit that
      changes a height above the viewport, a delete of the reference
      child (the reference moves to its neighbour without a jump),
      follow mode at the end, `PageStorageKey` restore, RTL layout.
- [x] `example/` app (dev only, not catalogued): a 10K-item forward
      list with jump-to-index and a reversed chat with paging, edits
      and live inserts — the Pixel surface for P2's owner check and
      RD10's review surface.
- [x] README rewritten from the tests (RD14).

Exit: the claims suite is fully green with nothing tagged `pending`;
the API of §2.2 is frozen for P3.

Owner check (Pixel, the example app): jump from item 0 to 5,000 lands
instantly with no blank frames; scroll up in the chat while messages
arrive — nothing moves; load older ten times — nothing moves; the
anchored message stays at 0.7 while pages load; rotate — heights
re-estimate, position kept.

### P3 — Adoption in Tendvine (M)

**P3a — `ConversationBody` first.** Deliverables:

- [ ] The body renders `ReaderView<ConversationEntry>` (§2.2) behind
      its existing props: `scrollController`, `jumpTarget`, `hasOlder`,
      `older`, `actions.onLoadOlder`, `actions.onAtBottomChanged`,
      `actions.onJumpToLatest`; `ConversationBodyActions` and
      `conversation_body.states.dart` stay; entries carry `key` and
      `typeKey` (`message`, `day`, `new`); `conversationTypeConfigs`
      with estimates (message 72, day 40, new 32; a
      `TextPremeasurer` estimator over the bubble style is optional).
- [ ] The history loader / intro becomes the trailing sliver, gated by
      the reader (the `SliverLayoutBuilder` goes).
- [ ] `_anchorIndexOf`, `_centerKey`, `center:` / `anchor:` and
      `_bottomThreshold` leave the body (whatever remains is P4).
- [ ] `conversation_page.dart` unchanged (`_jumpToLatest` still
      `jumpTo(0)` or the reduced-motion animate).
- [ ] States: `anchored on a message while older pages load` and
      `scrolled up with new below` added to the registry and the
      catalogue; no goldens.
- [ ] Tests: body widget tests over the states (the target lands at
      0.7; at-bottom flips at 48 px and drives the pill; the loader
      fires once per page and never at open); cubit tests unchanged.
- [ ] Pixel verification (seeded staging, two accounts):
  - [ ] jump from a push (`?m=`) into a room with ten pages of history:
        the target lands, the highlight plays, no blank frame;
  - [ ] jump from a search hit; "Jump to latest" from the anchored list;
  - [ ] ten-page paging without a visible shift;
  - [ ] offline send: the pending bubble appears at the bottom; when
        scrolled up nothing moves and "new below" counts;
  - [ ] a live edit, a live delete and a reaction while scrolled up:
        nothing moves;
  - [ ] keyboard open and close keeps the bottom; reduced motion on;
        200 % text size; TalkBack reads bubbles newest-first as today.

**P3b — `ThreadBody` (optional, forward proof).** Deliverables:

- [ ] `ReaderView` forward with `hasMoreAfter` from `hasMore`, the root
      at index 0, `LoadMoreFooter` as the trailing sliver; one state
      added; Pixel: a 200-reply thread pages without a shift.

**P3c** — home timeline: none (RD9). Long-form content: none (RD10).

### P4 — Remove the hand-rolled anchor code (S)

Deliverables:

- [ ] Delete what P3 left: the anchor index search, the centre key,
      the 0.7 constant (now one `ReaderAnchor` in the body), the
      `SliverLayoutBuilder` gate, the pixel threshold.
- [ ] `chat_feature_plan.md` §3.2, C3 and C8 notes point here; a polish
      log entry.
- [ ] Convention tests unchanged (the body is still props + callbacks);
      the size ledger stays empty.

Exit: `conversation_body.dart` renders the list in one expression and
carries no scroll arithmetic.

Owner check: the P3a Pixel list once more, after the deletion.

---

## 5. Tracker

| Phase | Title | Status | Commit(s) | Owner check |
| --- | --- | --- | --- | --- |
| P0 | Hygiene: own repo, fold the engine, fvm pin, lints and caps, dead widgets out, CI workflow | ☑ built 2026-09-24 | v2.0.0 | ☐ |
| P1 | Engine truths: a test per claim, reverse mapping, guards, view rebuilds, width detection, deferred jump, engine O(N) fix | ☑ built 2026-09-24 — folded into P2: the claims suite (`test/claims/`, 30 tests) is green against the new sliver, none tagged pending; the engine's error tree replaces the O(distance) walk | v2.0.0 | ☐ |
| P2 | The chat contract: `SliverReaderList`, generic items, `setItems` diff, anchor and end semantics, example app, README | ☑ built 2026-09-24 — 167 tests + 1 benchmark, analyze clean under Tendvine's lints, example app (document + chat), README from the tests | v2.0.0 | ☐ |
| P3a | Adoption: `ConversationBody` behind its props, states, tests, Pixel list (the "App" session, against v2.0.0) | ☑ built 2026-09-24 by the App session — a reversed `ReaderView<ConversationEntry>` behind the unchanged props, states and `JumpPaging`; two states added; Pixel 10 on the staging seed: one history fetch per open, no self-paging, live posts / edits / deletes while scrolled up moved nothing, the pill counted, a search hit landed anchored at 0.7 after one older page, keyboard and 200 % text keep the bottom. Not exercised: a ten-page room, TalkBack order | `99454c2c7` (tendvine, local) | ☐ |
| P3b | Adoption: `ThreadBody` (optional) | ☑ built 2026-09-24 by the App session — a forward `ReaderView<ThreadEntry>`, one state added; a long thread pages at the end, a short one at once | `99454c2c7` (tendvine, local) | ☐ |
| P4 | Remove the hand-rolled anchor code | ☑ built 2026-09-24 by the App session — `center:` anchor, `_anchorIndexOf`, the scroll listener and the `SliverLayoutBuilder` gate deleted; full non-golden suite 6,386 green | `99454c2c7` (tendvine, local) | ☐ |

Legend: ☐ not started · ◐ in progress · ☑ done (commit) · ✔ owner
verified · ⊘ blocked (reason). Update the row in the same commit as
the work.

Order: P0 → P1 → P2 → P3a → P4; P3b any time after P2.

**After the plan (2026-09-24, v2.1.0):** the App session's adoption
notes became four API additions (`onAnchorPlaced`, `setItems` with
the edge flags, an optional `initialWidth`, "an anchor on the newest
message means the end") and ten proven scenarios
(`test/claims/adoption_asks_test.dart`); a randomized stress walk
(`test/stress/`) found and fixed three reference-child defects (an
off-screen anchor pinning, a replayed jump, a placement short of the
viewport's origin); PageStorage restore became content-exact.

---

## 6. What the owner decides

1. **Vendor into the repo** (`packages/flutter_reader`) or keep a
   sibling folder that CI cannot see — RD1. Recommended: vendor.
2. **Fold the engine in** or keep it a pinned git dependency — RD2.
   Recommended: fold.
3. **Build the engine-backed sliver** (the real fix, L) or port
   Tendvine's `center:` trick into the package (cheaper, the engine
   stays decorative, live inserts still shift) — RD3. Recommended:
   the sliver.
4. The host owns the `ScrollController` — RD4. Recommended: yes.
5. Generic items, no `dynamic` — RD5. Recommended: yes.
6. `setItems` diff as the primary mutation — RD6. Recommended: yes.
7. Anchor by id with an alignment; 48 px end threshold with a
   callback — RD7. Recommended: yes.
8. Drop the Material search bar and highlight widget — RD8.
   Recommended: drop.
9. Home timeline out of scope — RD9. Recommended: out.
10. Long-form content waits for a surface; the `example/` app is the
    review surface — RD10. Recommended: wait.
11. Tendvine's lints and size caps in the package — RD11.
    Recommended: yes.
12. Remove eviction — RD12. Recommended: remove.
13. Keep the measurement helpers — RD13. Recommended: keep.
14. README rewritten from the tests — RD14. Recommended: yes.
15. Whether `ThreadBody` adoption (P3b) is wanted at all.
16. Which other timelines, if any, are candidates (long, paged, or
    jump-targeted from notifications).

---

## 7. Risks and open questions

- **`SliverReaderList` derives from `RenderSliverList.performLayout`**
  (about 250 lines, BSD). The SDK is pinned by fvm and the file names
  its source revision; every Flutter upgrade re-diffs it. This is the
  price of a list that uses the engine at all.
- **An anchor on an id that never arrives**: the cubit keeps paging
  to its cap and raises `jumpMissing` exactly as today; the reader
  holds the request and does nothing until the id appears.
- **`setItems` diff cost** is O(n) per emission with the id map; the
  feed window is ten pages of 50; P2 measures 5,000 items for the
  example app.
- **Semantics order in reverse** stays newest-first (as today). If the
  owner wants oldest-first for screen readers, the sliver's semantic
  index mapping is the single place to change; P3a's TalkBack check
  decides.
- **Estimates for message bodies**: type defaults are enough for the
  seed (unbuilt regions only); a `TextPremeasurer` estimator over the
  bubble's text style and paddings tightens far jumps and is optional.
- **`PageStorageKey` restore** restores the offset from the newest
  end; with offset 0 kept as the newest end (RD7) the stored offset
  keeps its meaning across rebuilds and room switches.
- **Keyboard insets** are the composer's as today; a reversed viewport
  keeps the bottom when the viewport shrinks.

---

## Appendix A — Probe log (2026-09-24, Flutter 3.47.1)

A scratch package with `flutter_reader: path: …` and one test file;
every probe prints what it saw and none asserts, so one run answers
all of them. Items are 50 px `SizedBox`es unless stated; the test
viewport is 800 × 600; "top" is the item whose top edge is nearest the
viewport top.

| Probe | Setup | Observation | Verdict |
| --- | --- | --- | --- |
| P1 | 10,000 items forward; count `itemBuilder` calls; `jumpToIndex(5000)`; pump | 22 builds before the jump, **5,000 during it**; item_5000 at the top afterwards | C1 refuted at the widget layer |
| P2 | 100 items reverse; read `visibility` at offset 0 | engine: first 0, last 12; on screen: item_88 at the top, item_99 at the bottom; `isAtEnd` true | C3a |
| P3 | 100 items reverse, `hasMoreBefore`, `onEdgeReached` prepends 20 | fired once at open with no scroll (120 items); after a 30 px drag fired 3 times (160 items); after another 30 px drag fired 4 times and `pixels` jumped 30 → 1,050 | C3b, C4 |
| P4 | 10 items of 20 px forward; `appendItems(5)`; pump twice | controller says 15; 10 `Text`s rendered; item_12 absent | C5 |
| P5 | 100 items reverse; drag up 500 px; `prependItems(20)` | `pixels` 500 → 1,500; top item_78 → item_58; bottom item_89 → item_69; engine `firstVisible` 30 | C2 (reverse), C3 |
| P6 | 100 items reverse; drag up 1,000 px; `jumpToId('item_5', alignment: 0.7)` | `pixels` 1,000 → 0; item_5 not on screen; top item_88 | C3c |
| P7 | 30 items; host width 800 → 300 | `registry.currentWidth` stays 800 | C6 |
| P8 | 100 items forward, real heights 30 / 90 alternating against a 50 px estimate; drag down 700; `prependItems(10)` | `pixels` 700 → 1,200; top item_12 → item_20 | C2 (forward) |
| P9 | 100 items reverse; drag up 500; `appendItems(1)`; host rebuild | `pixels` 500 → 500; top item_78 → item_79; bottom item_89 → item_90 (content shifted by one item) | keep-position on live insert missing |
| P10 | `jumpToId` from a sibling builder before the sliver's first layout | "Null check operator used on a null value" | the README's "don't" is a throw |
| P11 | engine only, 200,000 items; 100 × `jumpToId` far and near | far 236.1 µs average, near 5.6 µs | C1 engine part: O(distance) |

Reproduce: the probes became the first cases of `test/claims/` (and
`test/engine/jump_error_test.dart` for P11); against v1.0.0 they were
run from a scratch package with a path dependency and one test file,
which `tool/probes/` held until P2 replaced it. A second run gave the
same numbers (P11: 240 / 5.7 µs).

## Appendix B — Test inventory against the README's table

| Group | README says | Actual | File |
| --- | --- | --- | --- |
| VisibilityNotifier | 8 | 7 | `test/viewport/visibility_notifier_test.dart` |
| TextPremeasurer | 7 | 8 | `test/measurement/text_premeasurer_test.dart` |
| MeasurementScheduler | 7 | 6 | `test/measurement/measurement_scheduler_test.dart` |
| ReaderSearchController (+ SearchMatch) | 14 | 29 | `test/widgets/reader_search_controller_test.dart` |
| ReaderSearchBar | 4 | **0** | — |
| SearchHighlightText | 4 | **0** | — |
| ReaderView | 13 | 5 (+ 2 MeasuredItem) | `test/widgets/reader_view_test.dart` |
| ReaderController basic / batch / extent / edge / evict | 7 / 7 / 3 / 5 / 6 | 10 / 7 / 3 / 5 / 6 | `test/widgets/reader_controller_test.dart` |
| AnchorTracker | 9 | 6 | `test/viewport/anchor_viewport_test.dart` |
| **Total** | 94 | 94 | — |

Not covered by any test: reverse mode (0 mentions), a jump's build
cost, keeping position on any mutation through the widget, a width
change through the widget, `jumpToId` before layout, `animateToId`
alignment, `PageStorageKey` restore, RTL.

Engine suites (91, run on the pinned SDK from a copy of the git
checkout): `fenwick_tree_test` (11), `chunked_height_index_test` (31),
`item_registry_test` (14), `reader_engine_test` (26),
`scroll_compensator_test` (9) — all pass;
none exercises a reversed offset, because the engine has no notion of
one (that is the widget layer's job, and it does it wrong).
