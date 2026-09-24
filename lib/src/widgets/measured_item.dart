import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out height after each frame in which it
/// changed. [SliverReaderList] measures during layout and does not need
/// this; it serves custom scroll implementations over the engine.
class const MeasuredItem({
  required super.child,

  /// Called after layout with the measured height.
  required final ValueChanged<double> onMeasured,

  /// The item this slot shows; a change resets the last report.
  required final int itemIndex,
  super.key,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasuredItem(onMeasured: onMeasured, itemIndex: itemIndex);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMeasuredItem renderObject,
  ) {
    renderObject
      ..onMeasured = onMeasured
      ..itemIndex = itemIndex;
  }
}

/// The render object of [MeasuredItem].
class RenderMeasuredItem({
  required var ValueChanged<double> onMeasured,
  required var int _itemIndex,
}) extends RenderProxyBox {
  double? _lastReportedHeight;

  set itemIndex(int value) {
    if (value == _itemIndex) return;
    _itemIndex = value;
    _lastReportedHeight = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_lastReportedHeight == height) return;
    _lastReportedHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onMeasured(height));
  }
}
