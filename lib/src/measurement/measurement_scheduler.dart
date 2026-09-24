import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../engine/engine/reader_engine.dart';
import 'text_premeasurer.dart';

/// How to pre-measure one item type: the text to measure and its style.
class const PremeasureConfig<T>({
  required final String Function(T data) textExtractor,
  required final TextStyle style,
  final EdgeInsets padding = EdgeInsets.zero,
});

/// Pre-measures low-confidence items in batches after each frame, and
/// feeds the estimates to the engine as premeasured heights.
class MeasurementScheduler<T>({
  required final ReaderEngine<T> engine,
  required final TextPremeasurer premeasurer,
  required final Map<String, PremeasureConfig<T>> configs,

  /// Items measured per frame.
  final int batchSize = 10,

  /// Only items below this confidence are measured.
  final double confidenceThreshold = 0.5,

  /// Called once per [start] when no candidates remain.
  final VoidCallback? onComplete,
}) {
  bool _running = false;
  bool _scheduled = false;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _scheduleNext();
  }

  /// Stops after the batch in flight.
  void stop() => _running = false;

  /// Stops and disposes the premeasurer.
  void dispose() {
    stop();
    premeasurer.dispose();
  }

  /// Measures one batch now; returns how many items it measured.
  int measureBatch() {
    final candidates = engine.nextItemsToMeasure(
      count: batchSize,
      threshold: confidenceThreshold,
    );
    if (candidates.isEmpty) return 0;
    final estimates = <int, double>{};
    final width = engine.registry.currentWidth;
    for (final index in candidates) {
      final item = engine.itemAt(index);
      final config = configs[item.typeKey];
      if (config == null) continue;
      estimates[index] = premeasurer
          .measureText(
            text: config.textExtractor(item.data),
            style: config.style,
            maxWidth: width,
            padding: config.padding,
          )
          .height;
    }
    if (estimates.isNotEmpty) engine.reportEstimatedHeights(estimates);
    return estimates.length;
  }

  void _scheduleNext() {
    if (!_running || _scheduled) return;
    _scheduled = true;
    // A post-frame callback does not request a frame by itself; an idle
    // app would never run the batch.
    SchedulerBinding.instance
      ..scheduleFrame()
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (!_running) return;
        if (measureBatch() > 0) {
          _scheduleNext();
        } else {
          _running = false;
          onComplete?.call();
        }
      });
  }
}
