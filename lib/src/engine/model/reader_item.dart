/// A content item the engine tracks: an id for lookups, a type key that
/// selects its [ItemTypeConfig], and the payload the widget layer renders.
///
/// Framework-agnostic: nothing here knows about widgets.
class const ReaderItem<T>({
  /// Unique within one registry; jumps and diffs are keyed on it.
  required final String id,

  /// Key into the type configuration map.
  required final String typeKey,

  /// The payload, handed back to the item builder and the estimators.
  required final T data,
}) {
  @override
  String toString() => 'ReaderItem($id, $typeKey)';
}
