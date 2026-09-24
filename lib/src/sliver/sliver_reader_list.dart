import 'package:flutter/widgets.dart';

import '../controller/reader_anchor.dart';
import '../layout/reader_layout_model.dart';
import 'render_sliver_reader_list.dart';

/// The sliver behind [ReaderView]: an engine-backed list that seeds
/// layout at the item a scroll position or a jump asks for and keeps
/// one reference child fixed while items change around it.
///
/// Advanced use only: [ReaderView] wires a controller to it. The
/// [delegate] must build one keyed child per model index, in model
/// (layout) order, and answer [SliverChildBuilderDelegate.findChildIndexCallback]
/// through [ReaderLayoutModel.indexOfId].
class const SliverReaderList({
  required super.delegate,
  required final ReaderLayoutModel model,

  /// Bumped on every model mutation so the sliver re-lays out.
  required final int modelVersion,
  required final double atEndThreshold,
  required final ValueChanged<ReaderLayoutReport> onLayout,
  final ReaderAnchor? anchor,
  final ReaderJump? jump,
  super.key,
}) extends SliverMultiBoxAdaptorWidget {
  @override
  RenderSliverReaderList createRenderObject(BuildContext context) =>
      RenderSliverReaderList(
        childManager: context as SliverMultiBoxAdaptorElement,
        model: model,
        modelVersion: modelVersion,
        atEndThreshold: atEndThreshold,
        onLayout: onLayout,
        anchor: anchor,
        jump: jump,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverReaderList renderObject,
  ) {
    renderObject
      ..model = model
      ..modelVersion = modelVersion
      ..atEndThreshold = atEndThreshold
      ..onLayout = onLayout
      ..anchor = anchor
      ..jump = jump;
  }
}
