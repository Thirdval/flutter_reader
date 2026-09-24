import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../controller/reader_anchor.dart';
import '../layout/reader_layout_model.dart';

part 'render_sliver_reader_list_bookkeeping.dart';

/// Where a layout pass starts: a raw index and its layout offset.
class const _Seed(final int index, final double offset);

/// A placement to fulfil in this pass.
class const _Placement(
  final String id,
  final double alignment,
  final bool trailingEdge,
);

/// A sliver that lays out its children from an engine model.
///
/// Every pass starts from one *seed* child and expands outward, so the
/// sliver never builds what lies between two distant positions: a jump
/// seeds at the target item at its model offset. The seed is, in order,
/// a pending placement (a jump or a newly set anchor), the pinned anchor,
/// raw index 0 when the viewport is at its end (follow mode), else the
/// reference child of the previous pass (the first visible child, or a
/// neighbour when it was removed) at its previous layout offset. Layout
/// offsets are remembered by item id, so an insert or a removal before
/// the reference child moves nothing on screen; the drift between layout
/// and model offsets is settled with a scroll offset correction when the
/// run reaches raw index 0.
class RenderSliverReaderList({
  required super.childManager,
  required var ReaderLayoutModel _model,
  required var int _modelVersion,
  required var double _atEndThreshold,
  required var ValueChanged<ReaderLayoutReport> onLayout,
  var ReaderAnchor? _anchor,
  var ReaderJump? _jump,
}) extends RenderSliverMultiBoxAdaptor {
  /// The most leading children laid out beyond the cache window per pass
  /// while the viewport sits at its start.
  static const _maxLeadingFill = 32;

  final Map<String, double> _offsetsById = {};
  final Set<String> _attachedIds = {};
  List<String> _orderedIds = const [];
  String? _referenceId;
  int _fulfilledJumpSerial = -1;
  String? _placedAnchorId;

  ReaderLayoutModel get model => _model;
  set model(ReaderLayoutModel value) {
    if (identical(value, _model)) return;
    _model = value;
    _forget();
    markNeedsLayout();
  }

  set modelVersion(int value) {
    if (value == _modelVersion) return;
    _modelVersion = value;
    markNeedsLayout();
  }

  set atEndThreshold(double value) {
    if (value == _atEndThreshold) return;
    _atEndThreshold = value;
    markNeedsLayout();
  }

  set anchor(ReaderAnchor? value) {
    if (value == _anchor) return;
    _anchor = value;
    if (value == null || value.id != _placedAnchorId) _placedAnchorId = null;
    markNeedsLayout();
  }

  set jump(ReaderJump? value) {
    if (value == _jump) return;
    _jump = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    childManager
      ..didStartLayout()
      ..setDidUnderflow(false);
    final count = _model.itemCount;
    if (count == 0) {
      _dropAll();
      _forget();
      geometry = SliverGeometry.zero;
      _report(-1, -1, leading: true, trailing: true, drift: 0);
      childManager.didFinishLayout();
      return;
    }
    final scrollOffset = constraints.scrollOffset;
    final cacheStart = scrollOffset + constraints.cacheOrigin;
    final cacheEnd = cacheStart + constraints.remainingCacheExtent;
    final viewport = constraints.viewportMainAxisExtent;
    final childConstraints = constraints.asBoxConstraints();
    final atEnd =
        scrollOffset <= 0 ||
        scrollOffset + constraints.precedingScrollExtent <= _atEndThreshold;

    _restoreOffsets();
    final placement = _placement();
    final seed = _chooseSeed(placement, atEnd, cacheStart, cacheEnd, viewport);
    final seedChild = _materializeSeed(seed, childConstraints);
    if (seedChild == null) {
      _forget();
      geometry = SliverGeometry.zero;
      childManager.didFinishLayout();
      return;
    }
    final seedExtent = paintExtentOf(seedChild);
    _model.reportExtent(seed.index, seedExtent);

    if (placement != null) {
      _referenceId = placement.id;
      final edge = placement.trailingEdge
          ? seed.offset + seedExtent
          : seed.offset;
      final target = math.max(0.0, edge - placement.alignment * viewport);
      if ((target - scrollOffset).abs() > precisionErrorTolerance) {
        _snapshotOffsets();
        geometry = SliverGeometry(
          scrollOffsetCorrection: target - scrollOffset,
        );
        return;
      }
    }

    final earliest = _expandBackward(
      seedChild,
      seed,
      cacheStart,
      scrollOffset,
      childConstraints,
    );
    if (earliest == null) return; // a correction was issued
    final forward = _expandForward(seedChild, seed, cacheEnd, childConstraints);

    var leadingGarbage = 0;
    for (var c = firstChild; c != null && c != earliest; c = childAfter(c)) {
      leadingGarbage++;
    }
    var trailingGarbage = 0;
    for (
      var c = lastChild;
      c != null && c != forward.last;
      c = childBefore(c)
    ) {
      trailingGarbage++;
    }
    collectGarbage(leadingGarbage, trailingGarbage);
    assert(debugAssertChildListIsNonEmptyAndContiguous());

    final firstOffset = _offsetOf(firstChild!);
    final drift = firstOffset - _model.offsetAt(indexOf(firstChild!));
    final scrollExtent = forward.reachedEnd
        ? forward.end
        : math.max(forward.end, _model.totalExtent + drift);
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: calculatePaintOffset(
        constraints,
        from: firstOffset,
        to: forward.end,
      ),
      cacheExtent: calculateCacheOffset(
        constraints,
        from: firstOffset,
        to: forward.end,
      ),
      maxPaintExtent: scrollExtent,
      hasVisualOverflow:
          forward.end > scrollOffset + constraints.remainingPaintExtent ||
          scrollOffset > 0,
    );
    if (forward.reachedEnd) childManager.setDidUnderflow(true);

    _remember(atEnd, scrollOffset, constraints.remainingPaintExtent);
    _reportVisible(
      scrollOffset,
      constraints.remainingPaintExtent,
      trailing: forward.reachedEnd,
      drift: drift,
    );
    childManager.didFinishLayout();
  }

  // ── Seeding ──────────────────────────────────────────────────────────

  /// A pending jump, else a newly set anchor, when its item is loaded.
  _Placement? _placement() {
    if (_jump case final jump? when jump.serial != _fulfilledJumpSerial) {
      if (_model.indexOfId(jump.id) != null) {
        _fulfilledJumpSerial = jump.serial;
        return _Placement(jump.id, jump.alignment, jump.trailingEdge);
      }
    }
    if (_anchor case final anchor? when _placedAnchorId != anchor.id) {
      if (_model.indexOfId(anchor.id) != null) {
        _placedAnchorId = anchor.id;
        return _Placement(anchor.id, anchor.alignment, false);
      }
    }
    return null;
  }

  _Seed _chooseSeed(
    _Placement? placement,
    bool atEnd,
    double cacheStart,
    double cacheEnd,
    double viewport,
  ) {
    if (placement != null) {
      final raw = _model.indexOfId(placement.id)!;
      final known = _attachedIds.contains(placement.id)
          ? _offsetsById[placement.id]
          : null;
      return _Seed(raw, known ?? _model.offsetAt(raw));
    }
    if (_anchor case final anchor? when _placedAnchorId == anchor.id) {
      if (_stickySeedFor(anchor.id) case final seed?) return seed;
    }
    if (atEnd) return const _Seed(0, 0);
    final sticky = _stickySeed();
    if (sticky != null) {
      final near =
          sticky.offset <= cacheEnd + viewport &&
          sticky.offset + _model.extentAt(sticky.index) >=
              cacheStart - viewport;
      if (near) return sticky;
    }
    final raw = _model.indexAtOffset(cacheStart);
    return _Seed(raw, _model.offsetAt(raw));
  }

  /// Attaches and lays out the seed child, dropping children that would
  /// have to be walked over from afar.
  RenderBox? _materializeSeed(_Seed seed, BoxConstraints childConstraints) {
    if (firstChild != null) {
      final first = indexOf(firstChild!);
      final last = indexOf(lastChild!);
      if (seed.index >= first && seed.index <= last) {
        var child = firstChild;
        while (child != null && indexOf(child) != seed.index) {
          child = childAfter(child);
        }
        if (child != null) return _layoutSeed(child, seed, childConstraints);
        _dropAll();
      } else if (seed.index < first && first - seed.index <= _maxLeadingFill) {
        while (firstChild != null && indexOf(firstChild!) > seed.index) {
          if (insertAndLayoutLeadingChild(childConstraints) == null) break;
        }
        if (firstChild != null && indexOf(firstChild!) == seed.index) {
          return _layoutSeed(firstChild!, seed, childConstraints);
        }
        _dropAll();
      } else {
        _dropAll();
      }
    }
    if (!addInitialChild(index: seed.index, layoutOffset: seed.offset)) {
      return null;
    }
    return _layoutSeed(firstChild!, seed, childConstraints);
  }

  RenderBox _layoutSeed(RenderBox child, _Seed seed, BoxConstraints c) {
    _parentData(child).layoutOffset = seed.offset;
    child.layout(c, parentUsesSize: true);
    return child;
  }

  // ── Expansion ────────────────────────────────────────────────────────

  /// Lays out the children before the seed down to the cache start, and
  /// further at the viewport's start. Returns the earliest child, or
  /// null after issuing the correction that settles a drifted origin.
  RenderBox? _expandBackward(
    RenderBox seedChild,
    _Seed seed,
    double cacheStart,
    double scrollOffset,
    BoxConstraints childConstraints,
  ) {
    var child = seedChild;
    var index = seed.index;
    var offset = seed.offset;
    var filled = 0;
    while (index > 0 &&
        (offset > cacheStart ||
            (scrollOffset <= precisionErrorTolerance &&
                filled < _maxLeadingFill))) {
      var prev = childBefore(child);
      if (prev != null && indexOf(prev) != index - 1) {
        _dropBefore(child);
        prev = null;
      }
      if (prev == null) {
        prev = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        if (prev == null) break;
      } else {
        prev.layout(childConstraints, parentUsesSize: true);
      }
      final extent = paintExtentOf(prev);
      index -= 1;
      offset -= extent;
      if (offset <= cacheStart) filled++;
      _model.reportExtent(index, extent);
      _parentData(prev).layoutOffset = offset;
      child = prev;
    }
    final drifted =
        offset < -precisionErrorTolerance ||
        (index == 0 && offset > precisionErrorTolerance);
    if (drifted) {
      _shiftAll(-offset);
      _snapshotOffsets();
      geometry = SliverGeometry(scrollOffsetCorrection: -offset);
      return null;
    }
    return child;
  }

  /// Lays out the children after the seed up to the cache end.
  ({RenderBox last, double end, bool reachedEnd}) _expandForward(
    RenderBox seedChild,
    _Seed seed,
    double cacheEnd,
    BoxConstraints childConstraints,
  ) {
    final count = _model.itemCount;
    var child = seedChild;
    var index = seed.index;
    var end = seed.offset + paintExtentOf(seedChild);
    while (end < cacheEnd && index + 1 < count) {
      var next = childAfter(child);
      if (next == null || indexOf(next) != index + 1) {
        next = insertAndLayoutChild(
          childConstraints,
          after: child,
          parentUsesSize: true,
        );
        if (next == null) break;
      } else {
        next.layout(childConstraints, parentUsesSize: true);
      }
      index += 1;
      final extent = paintExtentOf(next);
      _model.reportExtent(index, extent);
      _parentData(next).layoutOffset = end;
      end += extent;
      child = next;
    }
    return (last: child, end: end, reachedEnd: index + 1 >= count);
  }

  // ── Garbage ──────────────────────────────────────────────────────────

  double _extentOf(RenderBox child) => paintExtentOf(child);

  void _dropAll() {
    if (firstChild != null) collectGarbage(childCount, 0);
  }

  void _dropBefore(RenderBox child) {
    var n = 0;
    for (var c = firstChild; c != null && c != child; c = childAfter(c)) {
      n++;
    }
    if (n > 0) collectGarbage(n, 0);
  }
}
