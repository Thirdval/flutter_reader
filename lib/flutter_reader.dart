/// An engine-backed scrollable list: exact jumps to any item without
/// building what lies between, a reference item kept fixed while content
/// changes around it, reverse (chat) mode, lazy loading gated on the
/// cache extent, and text search.
library;

// Engine (pure Dart)
export 'src/engine/core/chunked_height_index.dart';
export 'src/engine/core/fenwick_tree.dart';
export 'src/engine/engine/reader_engine.dart';
export 'src/engine/model/height_entry.dart';
export 'src/engine/model/item_type_config.dart';
export 'src/engine/model/reader_item.dart';
export 'src/engine/registry/item_registry.dart';
export 'src/engine/scroll/scroll_compensator.dart';

// Widget layer
export 'src/controller/item_diff.dart';
export 'src/controller/reader_anchor.dart';
export 'src/controller/reader_controller.dart';
export 'src/layout/reader_layout_model.dart';
export 'src/sliver/render_sliver_reader_list.dart';
export 'src/sliver/sliver_reader_list.dart';
export 'src/widgets/measured_item.dart';
export 'src/widgets/reader_view.dart';

// Measurement helpers
export 'src/measurement/measurement_scheduler.dart';
export 'src/measurement/text_premeasurer.dart';

// Search
export 'src/search/reader_search_controller.dart';
export 'src/search/search_highlight.dart';
