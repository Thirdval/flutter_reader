part of 'render_sliver_reader_list.dart';

/// The sliver's memory between passes: layout offsets by item id, the
/// order of the attached children, and the report it hands the
/// controller.
extension _Bookkeeping on RenderSliverReaderList {
  SliverMultiBoxAdaptorParentData _parentData(RenderBox child) =>
      child.parentData! as SliverMultiBoxAdaptorParentData;

  double _offsetOf(RenderBox child) => _parentData(child).layoutOffset!;

  /// Restores each attached child's layout offset from the last pass by
  /// id; the element may have moved children to new indices.
  void _restoreOffsets() {
    _attachedIds.clear();
    final count = _model.itemCount;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      final id = index < count ? _model.idAt(index) : null;
      if (id != null) _attachedIds.add(id);
      _parentData(child).layoutOffset = id == null ? null : _offsetsById[id];
    }
  }

  void _snapshotOffsets() {
    _offsetsById.clear();
    final count = _model.itemCount;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      final offset = _parentData(child).layoutOffset;
      if (index < count && offset != null) {
        _offsetsById[_model.idAt(index)] = offset;
      }
    }
  }

  void _remember(bool atEnd, double scrollOffset, double paintExtent) {
    _snapshotOffsets();
    final ordered = <String>[];
    String? firstVisible;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final id = _model.idAt(indexOf(child));
      ordered.add(id);
      if (firstVisible == null &&
          _offsetOf(child) + _extentOf(child) > scrollOffset) {
        firstVisible = id;
      }
    }
    _orderedIds = ordered;
    // The anchor is the reference only while it is on screen and does
    // not mean "the end"; an off-screen anchor would move what is read.
    if (_anchor case final anchor?
        when _placedAnchorId == anchor.id &&
            !_anchorMeansEnd &&
            _isVisible(anchor.id, scrollOffset, paintExtent)) {
      _referenceId = anchor.id;
    } else {
      _referenceId = firstVisible ?? ordered.firstOrNull;
    }
  }

  bool _isVisible(String id, double scrollOffset, double paintExtent) {
    final raw = _model.indexOfId(id);
    final offset = _offsetsById[id];
    if (raw == null || offset == null) return false;
    return offset + _model.extentAt(raw) > scrollOffset &&
        offset < scrollOffset + paintExtent;
  }

  void _shiftAll(double delta) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = _parentData(child);
      if (data.layoutOffset != null) {
        data.layoutOffset = data.layoutOffset! + delta;
      }
    }
  }

  /// Drops everything remembered between passes, placements included:
  /// a new model (a controller swap) or an emptied list starts over.
  void _forget() {
    _offsetsById.clear();
    _attachedIds.clear();
    _orderedIds = const [];
    _referenceId = null;
    _placedAnchorId = null;
    _anchorMeansEnd = false;
    _settling = null;
    _settlePasses = 0;
  }

  void _reportVisible(
    double scrollOffset,
    double paintExtent, {
    required bool trailing,
    required double drift,
    String? placedAnchor,
  }) {
    var first = -1;
    var last = -1;
    var firstOffset = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final offset = _offsetOf(child);
      if (offset + _extentOf(child) <= scrollOffset) continue;
      if (offset >= scrollOffset + paintExtent) break;
      if (first < 0) {
        first = indexOf(child);
        firstOffset = offset - scrollOffset;
      }
      last = indexOf(child);
    }
    _report(
      first,
      last,
      leading: indexOf(firstChild!) == 0,
      trailing: trailing || indexOf(lastChild!) == _model.itemCount - 1,
      drift: drift,
      placedAnchor: placedAnchor,
      firstVisibleOffset: firstOffset,
      paintExtent: paintExtent,
    );
  }

  void _report(
    int first,
    int last, {
    required bool leading,
    required bool trailing,
    required double drift,
    String? placedAnchor,
    double firstVisibleOffset = 0,
    double paintExtent = 0,
  }) => onLayout(
    ReaderLayoutReport(
      firstVisibleRaw: first,
      lastVisibleRaw: last,
      leadingEdgeReached: leading,
      trailingEdgeReached: trailing,
      drift: drift,
      fulfilledJumpSerial: _fulfilledJumpSerial,
      placedAnchorId: placedAnchor,
      firstVisibleOffset: firstVisibleOffset,
      paintExtent: paintExtent,
    ),
  );

  _Seed? _stickySeedFor(String id) {
    if (!_attachedIds.contains(id)) return null;
    final raw = _model.indexOfId(id);
    final offset = _offsetsById[id];
    return raw == null || offset == null ? null : _Seed(raw, offset);
  }

  /// The reference child of the last pass, else the nearest survivor
  /// after it in that pass's order (so what follows it on screen holds
  /// its place when it is removed), else before it, else any survivor.
  _Seed? _stickySeed() {
    if (_referenceId case final id?) {
      if (_stickySeedFor(id) case final seed?) return seed;
      final at = _orderedIds.indexOf(id);
      for (var i = at + 1; i < _orderedIds.length; i++) {
        if (_stickySeedFor(_orderedIds[i]) case final seed?) return seed;
      }
      for (var i = at - 1; i >= 0; i--) {
        if (_stickySeedFor(_orderedIds[i]) case final seed?) return seed;
      }
    }
    for (final id in _orderedIds) {
      if (_stickySeedFor(id) case final seed?) return seed;
    }
    return null;
  }

  /// A pending jump, else a newly set anchor, when its item is loaded.
  /// An anchor whose item vanished is placed again when it returns.
  _Placement? _placement() {
    if (_jump case final jump? when jump.serial != _fulfilledJumpSerial) {
      if (_model.indexOfId(jump.id) != null) {
        _fulfilledJumpSerial = jump.serial;
        return _Placement(jump.id, jump.alignment, jump.trailingEdge);
      }
    }
    if (_anchor case final anchor?) {
      if (_model.indexOfId(anchor.id) == null) {
        _placedAnchorId = null;
      } else if (_placedAnchorId != anchor.id) {
        _placedAnchorId = anchor.id;
        _anchorMeansEnd = _model.indexOfId(anchor.id) == 0;
        return _Placement(anchor.id, anchor.alignment, false, isAnchor: true);
      }
    }
    return null;
  }
}
