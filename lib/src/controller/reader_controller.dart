// ignore_for_file: initialize_in_field_declaration

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../engine/engine/reader_engine.dart';
import '../engine/model/item_type_config.dart';
import '../engine/model/reader_item.dart';
import '../engine/registry/item_registry.dart';
import '../layout/reader_layout_model.dart';
import 'item_diff.dart';
import 'reader_anchor.dart';

part 'reader_controller_navigation.dart';

/// Owns the items and their height model for a [ReaderView], and offers
/// navigation, lazy loading and visibility over them. Indices in this
/// API are data indices (the order items were given); the view maps
/// them to layout order in reverse mode.
///
/// Hand the controller the whole list on every change through
/// [setItems] (it diffs by id), or mutate it with the batch methods.
class ReaderController<T>({
  required List<T> items,

  /// The stable id of an item; jumps, anchors and diffs are keyed on it.
  required final String Function(T item) idOf,

  /// The type key of an item, into [typeConfigs].
  required final String Function(T item) typeKeyOf,
  required Map<String, ItemTypeConfig<T>> typeConfigs,

  /// The width estimators run at before the first layout; the first
  /// layout re-estimates at the real width. 0 means unknown.
  double initialWidth = 0,
  int bucketSize = 128,

  /// Whether content exists before the first item (older history).
  var bool _hasMoreBefore = false,

  /// Whether content exists after the last item.
  var bool _hasMoreAfter = false,

  /// Called, after the frame, when the edge of the loaded items enters
  /// the cache window and that edge has more; once per page, until the
  /// next mutation at that edge.
  var void Function(LoadDirection direction)? onEdgeReached,

  /// How close to the end of the list (raw offset 0 in reverse mode) the
  /// viewport counts as "at the end", in pixels.
  var double atEndThreshold = 0,

  /// Called when [isAtEnd] changes.
  var ValueChanged<bool>? onAtEndChanged,
}) extends ChangeNotifier {
  // The registry is built from the constructor's item list, which is not
  // a field; the initializer list is the only place that can read it
  // (hence the file-level ignore of initialize_in_field_declaration).
  this
    : _registry = ItemRegistry<T>.build(
        items: [
          for (final item in items)
            ReaderItem<T>(id: idOf(item), typeKey: typeKeyOf(item), data: item),
        ],
        typeConfigs: typeConfigs,
        initialWidth: initialWidth,
        bucketSize: bucketSize,
      );

  final ItemRegistry<T> _registry;
  late final ReaderEngine<T> _engine = ReaderEngine<T>(registry: _registry);
  late ReaderLayoutModel _model = ForwardLayoutModel<T>(_registry);
  final ValueNotifier<VisibilityState> _visibility = ValueNotifier(
    const VisibilityState(),
  );
  ScrollController? _scrollController;
  bool _reverse = false;
  int _modelVersion = 0;
  int _jumpSerial = 0;
  ReaderJump? _jump;
  bool _isAtEnd = true;
  bool _loadingBefore = false;
  bool _loadingAfter = false;
  ReaderLayoutReport? _report;
  bool _dispatchScheduled = false;

  // ── Items ────────────────────────────────────────────────────────────

  /// Whether content exists before the first item. Setting it to true
  /// fires [onEdgeReached] after the frame if that edge is already in
  /// the cache window.
  bool get hasMoreBefore => _hasMoreBefore;
  set hasMoreBefore(bool value) {
    if (value == _hasMoreBefore) return;
    _hasMoreBefore = value;
    if (value) _scheduleDispatch();
  }

  /// Whether content exists after the last item; see [hasMoreBefore].
  bool get hasMoreAfter => _hasMoreAfter;
  set hasMoreAfter(bool value) {
    if (value == _hasMoreAfter) return;
    _hasMoreAfter = value;
    if (value) _scheduleDispatch();
  }

  int get itemCount => _registry.itemCount;
  T itemAt(int index) => _registry.itemAt(index).data;
  int? indexOfId(String id) => _registry.indexOfId(id);
  Iterable<T> get items => Iterable.generate(itemCount, itemAt);

  /// The engine over the same registry, for measurement helpers.
  ReaderEngine<T> get engine => _engine;
  ItemRegistry<T> get registry => _registry;

  /// Replaces the list: items keep their heights by id, removals and
  /// insertions are applied as batches, moved items are re-inserted.
  /// Resets the loading guard of an edge that gained items, and sets
  /// [hasMoreBefore] / [hasMoreAfter] when given.
  void setItems(List<T> items, {bool? hasMoreBefore, bool? hasMoreAfter}) {
    final diff = diffItems<T>(
      oldIds: [for (var i = 0; i < itemCount; i++) _registry.idAt(i)],
      newItems: items,
      idOf: idOf,
    );
    for (final op in diff.ops) {
      switch (op) {
        case RemoveItems<T>(:final start, :final count):
          _registry.removeRange(start, count);
        case InsertItems<T>(:final index, :final items):
          _registry.insertAll(index, _wrap(items));
      }
    }
    for (var i = 0; i < items.length; i++) {
      _registry.setItem(i, _wrapOne(items[i]));
    }
    if (diff.insertedAtStart) _loadingBefore = false;
    if (diff.insertedAtEnd) _loadingAfter = false;
    if (hasMoreBefore != null) this.hasMoreBefore = hasMoreBefore;
    if (hasMoreAfter != null) this.hasMoreAfter = hasMoreAfter;
    _changed();
  }

  /// Appends [items]; resets the "after" loading guard.
  void appendItems(List<T> items, {List<double?>? estimatedHeights}) {
    _loadingAfter = false;
    if (items.isNotEmpty) {
      _registry.insertAll(
        itemCount,
        _wrap(items),
        estimatedHeights: estimatedHeights,
      );
    }
    _changed();
  }

  /// Prepends [items]; resets the "before" loading guard.
  void prependItems(List<T> items, {List<double?>? estimatedHeights}) {
    _loadingBefore = false;
    if (items.isNotEmpty) {
      _registry.insertAll(0, _wrap(items), estimatedHeights: estimatedHeights);
    }
    _changed();
  }

  void insertItems(
    int index,
    List<T> items, {
    List<double?>? estimatedHeights,
  }) {
    if (items.isNotEmpty) {
      _registry.insertAll(
        index,
        _wrap(items),
        estimatedHeights: estimatedHeights,
      );
    }
    _changed();
  }

  void removeItems(int startIndex, int count) {
    if (count <= 0) return;
    _registry.removeRange(startIndex, count);
    _changed();
  }

  /// Replaces the item at [index] (same id or a new one); its height stays.
  void updateItem(int index, T item) {
    _registry.setItem(index, _wrapOne(item));
    _changed();
  }

  // ── Navigation ───────────────────────────────────────────────────────

  /// Places the item's leading edge at [alignment] (a fraction of the
  /// viewport from its leading edge) inside the next layout. Nothing in
  /// between is built. An unknown id is a no-op.
  void jumpToId(String id, {double alignment = 0}) {
    if (!_registry.containsId(id)) return;
    _request(id, alignment, trailingEdge: false);
  }

  void jumpToIndex(int index, {double alignment = 0}) =>
      jumpToId(_registry.idAt(index), alignment: alignment);

  /// Scrolls to the last item (offset 0 in reverse mode).
  void scrollToEnd() {
    if (itemCount == 0) return;
    _request(_registry.idAt(itemCount - 1), 1, trailingEdge: true);
  }

  /// Whether the viewport is within [atEndThreshold] of the end of the
  /// list: offset 0 in reverse mode, the last item otherwise.
  bool get isAtEnd => _isAtEnd;

  /// The items intersecting the viewport, in data indices; updated
  /// after each frame.
  ValueListenable<VisibilityState> get visibility => _visibility;

  // ── View plumbing ────────────────────────────────────────────────────

  /// Attaches to the view's scroll controller. Called by [ReaderView].
  void attach(ScrollController scrollController, {required bool reverse}) {
    if (identical(_scrollController, scrollController) && reverse == _reverse) {
      return;
    }
    _scrollController?.removeListener(_onScroll);
    _scrollController = scrollController..addListener(_onScroll);
    if (reverse != _reverse) {
      _reverse = reverse;
      _model = reverse
          ? ReverseLayoutModel<T>(_registry)
          : ForwardLayoutModel<T>(_registry);
    }
  }

  void detach() {
    _scrollController?.removeListener(_onScroll);
    _scrollController = null;
  }

  /// The layout model in the attached direction.
  ReaderLayoutModel get layoutModel => _model;
  int get modelVersion => _modelVersion;
  ReaderJump? get pendingJump => _jump;

  /// Re-estimates heights for [width]. Called from the view's layout;
  /// notifies nobody.
  void reportWidth(double width) {
    if (width <= 0 || width == _registry.currentWidth) return;
    _registry.onWidthChanged(width);
    _modelVersion++;
  }

  /// Receives each layout pass's report. Called from the sliver's layout;
  /// side effects run after the frame.
  void onLayoutReport(ReaderLayoutReport report) {
    _report = report;
    _scheduleDispatch();
  }

  void _scheduleDispatch() {
    if (_dispatchScheduled) return;
    _dispatchScheduled = true;
    SchedulerBinding.instance
      ..scheduleFrame()
      ..addPostFrameCallback((_) {
        _dispatchScheduled = false;
        _dispatch();
      });
  }

  // ── Private ──────────────────────────────────────────────────────────

  ScrollPosition? get _position {
    final controller = _scrollController;
    return controller != null && controller.hasClients
        ? controller.position
        : null;
  }

  List<ReaderItem<T>> _wrap(List<T> items) => [
    for (final item in items) _wrapOne(item),
  ];

  ReaderItem<T> _wrapOne(T item) =>
      ReaderItem<T>(id: idOf(item), typeKey: typeKeyOf(item), data: item);

  void _request(String id, double alignment, {required bool trailingEdge}) {
    _jump = ReaderJump(
      id: id,
      serial: ++_jumpSerial,
      alignment: alignment,
      trailingEdge: trailingEdge,
    );
    notifyListeners();
  }

  void _changed() {
    _modelVersion++;
    notifyListeners();
  }

  void _onScroll() => _updateAtEnd();

  void _updateAtEnd() {
    final position = _position;
    final atEnd = position == null
        ? true
        : _reverse
        ? position.pixels <= position.minScrollExtent + atEndThreshold
        : position.pixels >= position.maxScrollExtent - atEndThreshold;
    if (atEnd == _isAtEnd) return;
    _isAtEnd = atEnd;
    onAtEndChanged?.call(atEnd);
  }

  void _dispatch() {
    final report = _report;
    if (report == null) return;
    if (_jump case final jump? when jump.serial == report.fulfilledJumpSerial) {
      _jump = null; // fulfilled: a fresh sliver must not replay it
    }
    if (report.firstVisibleRaw < 0) {
      _visibility.value = const VisibilityState();
    } else {
      final a = _model.dataIndexOf(report.firstVisibleRaw);
      final b = _model.dataIndexOf(report.lastVisibleRaw);
      _visibility.value = VisibilityState(
        firstVisible: a < b ? a : b,
        lastVisible: a < b ? b : a,
        anchorIndex: a < b ? a : b,
      );
    }
    _updateAtEnd();
    final beforeReached = _reverse
        ? report.trailingEdgeReached
        : report.leadingEdgeReached;
    final afterReached = _reverse
        ? report.leadingEdgeReached
        : report.trailingEdgeReached;
    final callback = onEdgeReached;
    if (callback == null) return;
    if (_hasMoreBefore && !_loadingBefore && beforeReached) {
      _loadingBefore = true;
      callback(LoadDirection.before);
    }
    if (_hasMoreAfter && !_loadingAfter && afterReached) {
      _loadingAfter = true;
      callback(LoadDirection.after);
    }
  }

  @override
  void dispose() {
    detach();
    _visibility.dispose();
    super.dispose();
  }
}
