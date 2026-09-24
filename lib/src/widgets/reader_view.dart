import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controller/reader_anchor.dart';
import '../controller/reader_controller.dart';
import '../sliver/sliver_reader_list.dart';

/// Builds the widget for the item at data [index].
typedef ReaderItemBuilder<T> = Widget Function(
  BuildContext context,
  int index,
  T item,
);

/// An engine-backed list over a [ReaderController].
///
/// A [CustomScrollView] on the host's [scrollController] with the
/// controller's items in one [SliverReaderList], between optional
/// [leadingSlivers] and [trailingSlivers]. In [reverse] mode the last
/// item sits at offset 0 (a chat pinned to its newest message). The
/// view rebuilds when the controller changes; the sliver keeps what is
/// on screen fixed while items change around it.
class const ReaderView<T>({
  required final ReaderController<T> controller,

  /// The scroll controller the host owns (its `jumpTo(0)` is "the end"
  /// in reverse mode; a `PageStorageKey` on this widget restores it).
  required final ScrollController scrollController,
  required final ReaderItemBuilder<T> itemBuilder,
  final bool reverse = false,

  /// The item to keep pinned at an alignment; see [ReaderAnchor].
  final ReaderAnchor? anchor,

  /// Called, after the frame, when [anchor] has landed at its alignment:
  /// at once for a loaded item, or when a later [ReaderController.setItems]
  /// brings it. Start a highlight here rather than when the anchor is set.
  final ValueChanged<String>? onAnchorPlaced,
  final List<Widget> leadingSlivers = const [],
  final List<Widget> trailingSlivers = const [],
  final EdgeInsetsGeometry? padding,
  final ScrollPhysics? physics,
  final ScrollCacheExtent? scrollCacheExtent,
  final bool addAutomaticKeepAlives = false,
  final bool addSemanticIndexes = true,

  /// Rebuilds the visible items when it notifies (search highlights).
  final Listenable? itemUpdateListenable,

  /// With a [PageStorageKey] as [key], the view also remembers the first
  /// visible item and its offset, and places it again when it is rebuilt
  /// under the same key: the same content returns even after heights
  /// changed. The scroll offset alone restores approximately.
  super.key,
}) extends StatefulWidget {
  @override
  State<ReaderView<T>> createState() => _ReaderViewState<T>();
}

class const _StorageIdentifier(final Key key) {
  @override
  bool operator ==(Object other) =>
      other is _StorageIdentifier && other.key == key;

  @override
  int get hashCode => Object.hash(_StorageIdentifier, key);
}

class _ReaderViewState<T>() extends State<ReaderView<T>> {
  static const _restoreSerial = -2;
  ReaderJump? _restore;

  PageStorageBucket? get _storage =>
      widget.key is PageStorageKey ? PageStorage.maybeOf(context) : null;

  void _onLayout(ReaderLayoutReport report) {
    widget.controller.onLayoutReport(report);
    if (report.fulfilledJumpSerial == _restoreSerial) _restore = null;
    if (report.placedAnchorId case final id?) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAnchorPlaced?.call(id);
      });
    }
    if (report.firstVisibleRaw >= 0 && _storage != null) {
      final model = widget.controller.layoutModel;
      final saved = (
        id: model.idAt(report.firstVisibleRaw),
        offset: report.firstVisibleOffset,
        extent: report.paintExtent,
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _storage?.writeState(
          context,
          saved,
          identifier: _StorageIdentifier(widget.key!),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.attach(widget.scrollController, reverse: widget.reverse);
    final saved = _storage?.readState(
      context,
      identifier: _StorageIdentifier(widget.key!),
    ) as Object?;
    if (saved case (
      id: final String id,
      offset: final double offset,
      extent: final double extent,
    )) {
      _restore = ReaderJump(
        id: id,
        serial: _restoreSerial,
        alignment: extent > 0 ? offset / extent : 0,
      );
    }
  }

  @override
  void didUpdateWidget(ReaderView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
    }
    widget.controller.attach(widget.scrollController, reverse: widget.reverse);
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final controller = widget.controller;
        controller.reportWidth(constraints.maxWidth);
        final model = controller.layoutModel;
        final sliver = SliverReaderList(
          model: model,
          modelVersion: controller.modelVersion,
          atEndThreshold: controller.atEndThreshold,
          onLayout: _onLayout,
          anchor: widget.anchor,
          jump: controller.pendingJump ?? _restore,
          delegate: SliverChildBuilderDelegate(
            (context, rawIndex) {
              if (rawIndex < 0 || rawIndex >= model.itemCount) return null;
              final index = model.dataIndexOf(rawIndex);
              final item = controller.itemAt(index);
              Widget child = widget.itemBuilder(context, index, item);
              if (widget.itemUpdateListenable case final listenable?) {
                child = ListenableBuilder(
                  listenable: listenable,
                  builder: (context, _) =>
                      widget.itemBuilder(context, index, item),
                );
              }
              return KeyedSubtree(
                key: ValueKey<String>(model.idAt(rawIndex)),
                child: child,
              );
            },
            childCount: model.itemCount,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? model.indexOfId(key.value) : null,
            addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
            addSemanticIndexes: widget.addSemanticIndexes,
            // "Item n of m" counts in data order in both directions.
            semanticIndexCallback: (_, rawIndex) => model.dataIndexOf(rawIndex),
          ),
        );
        return CustomScrollView(
          controller: widget.scrollController,
          reverse: widget.reverse,
          physics: widget.physics,
          scrollCacheExtent: widget.scrollCacheExtent,
          slivers: [
            ...widget.leadingSlivers,
            if (widget.padding case final padding?)
              SliverPadding(padding: padding, sliver: sliver)
            else
              sliver,
            ...widget.trailingSlivers,
          ],
        );
      },
    ),
  );
}
