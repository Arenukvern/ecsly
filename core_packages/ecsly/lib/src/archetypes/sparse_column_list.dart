import 'dart:typed_data';

import '../components/columns/data_column.dart';
import '../components/component.dart';

/// Sparse list implementation for archetype columns that provides O(1) lookup
/// while only storing columns that exist (typically 2-10 per archetype).
///
/// Uses a fixed-size Int32List mapping for ComponentId.value to column index,
/// reducing memory overhead from Map-based storage.
///
/// Memory trade-off:
/// - Fixed: 1KB Int32List (256 * 4 bytes) + N pointers + N ComponentIds
/// - For 10 components: ~1KB + 80 bytes vs ~200 bytes (Map)
/// - Acceptable overhead for O(1) performance in hot path
class SparseColumnList {
  /// Dense storage for actual column objects (only existing columns)
  final List<DataColumn> _columns = [];

  /// ComponentId.value → column index mapping (-1 = not present)
  /// Size 256 to cover ComponentId.maxValue range
  final Int32List _idToIndex = Int32List(ComponentId.maxValue + 1)
    ..fillRange(0, ComponentId.maxValue + 1, -1);

  /// Reverse mapping for iteration (index → ComponentId)
  final List<ComponentId> _indexToId = [];

  /// Get all component ID and column pairs (for iteration)
  Iterable<(ComponentId, DataColumn)> get entries sync* {
    for (var i = 0; i < _columns.length; i++) {
      yield (_indexToId[i], _columns[i]);
    }
  }

  /// Get number of columns (O(1))
  int get length => _columns.length;

  /// Get all columns (for iteration)
  Iterable<DataColumn> get values => _columns;

  /// Add a column for a component ID (O(1))
  void add(final ComponentId componentId, final DataColumn column) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    if (_idToIndex[componentId.value] >= 0) {
      // Column already exists - this is expected behavior in Archetype.addColumn
      return;
    }

    final newIndex = _columns.length;
    _columns.add(column);
    _indexToId.add(componentId);
    _idToIndex[componentId.value] = newIndex;
  }

  /// Check if column exists for component ID (O(1))
  bool contains(final ComponentId componentId) {
    if (!componentId.isValid) return false;
    return _idToIndex[componentId.value] >= 0;
  }

  /// Get column for a component ID (O(1))
  DataColumn? getColumn(final ComponentId componentId) {
    if (!componentId.isValid) return null;
    final index = _idToIndex[componentId.value];
    return index >= 0 ? _columns[index] : null;
  }

  /// Remove a column for a component ID (O(1) via swap-with-last)
  void remove(final ComponentId componentId) {
    if (!componentId.isValid) return;

    final index = _idToIndex[componentId.value];
    if (index < 0) return; // Not present

    final lastIndex = _columns.length - 1;

    if (index != lastIndex) {
      // Swap with last element
      final lastComponentId = _indexToId[lastIndex];

      // Swap columns
      _columns[index] = _columns[lastIndex];

      // Swap reverse mappings
      _indexToId[index] = lastComponentId;

      // Update forward mapping for the swapped element
      _idToIndex[lastComponentId.value] = index;
    }

    // Remove last element
    _columns.removeLast();
    _indexToId.removeLast();
    _idToIndex[componentId.value] = -1;
  }
}
