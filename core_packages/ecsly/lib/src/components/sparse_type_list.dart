import '../components/component.dart';

/// Sparse list implementation for component type mapping that provides O(1) lookup
/// while handling hash collisions with linear probing.
///
/// This implementation is a fixed-size open-addressing hash table optimized for
/// small, bounded registries (component IDs are capped at 256).
class SparseTypeList {
  /// Fixed-size table. Power-of-2 enables fast bitmask modulo.
  static const int _arraySize = 1024;
  static final Object _tombstone = Object();

  final List<Object?> _keys = List.filled(_arraySize, null);
  final List<ComponentId?> _values = List.filled(_arraySize, null);
  int _length = 0;

  /// Get collision count for debugging/monitoring.
  ///
  /// Counts entries that are not stored in their home slot.
  int get collisionCount {
    var collisions = 0;
    for (var i = 0; i < _arraySize; i++) {
      final key = _keys[i];
      if (key is Type) {
        final home = _getIndex(key);
        if (home != i) collisions++;
      }
    }
    return collisions;
  }

  /// Get total number of collisions (alias for collisionCount)
  int get totalCollisions => collisionCount;

  /// Get collision rate as a percentage (0.0 to 1.0)
  double get collisionRate => _length == 0 ? 0.0 : collisionCount / _length;

  /// Get maximum probe distance of any entry from its home slot.
  int get maxCollisionsAtSingleIndex {
    var maxDistance = 0;
    for (var i = 0; i < _arraySize; i++) {
      final key = _keys[i];
      if (key is Type) {
        final home = _getIndex(key);
        final distance = (i - home) & (_arraySize - 1);
        if (distance > maxDistance) maxDistance = distance;
      }
    }
    return maxDistance;
  }

  /// Get all registered Type-ComponentId pairs (for iteration)
  Iterable<(Type, ComponentId)> get entries sync* {
    for (var i = 0; i < _arraySize; i++) {
      final key = _keys[i];
      if (key is Type) {
        final id = _values[i];
        if (id != null) yield (key, id);
      }
    }
  }

  /// Get number of registered types (O(1))
  int get length => _length;

  /// Check if a Type is registered (O(1))
  bool contains(final Type type) => get(type) != null;

  /// Get the ComponentId for a given Type (O(1) expected).
  ComponentId? get(final Type type) {
    var index = _getIndex(type);
    for (var probes = 0; probes < _arraySize; probes++) {
      final key = _keys[index];
      if (key == null) return null;
      if (key == type) return _values[index];
      index = (index + 1) & (_arraySize - 1);
    }
    return null;
  }

  /// Set the ComponentId for a given Type (O(1) expected).
  void set(final Type type, final ComponentId componentId) {
    var index = _getIndex(type);
    int firstTombstone = -1;

    for (var probes = 0; probes < _arraySize; probes++) {
      final key = _keys[index];

      if (key == null) {
        final insertIndex = firstTombstone >= 0 ? firstTombstone : index;
        _keys[insertIndex] = type;
        _values[insertIndex] = componentId;
        _length++;
        return;
      }

      if (key == type) {
        _values[index] = componentId;
        return;
      }

      if (identical(key, _tombstone) && firstTombstone < 0) {
        firstTombstone = index;
      }

      index = (index + 1) & (_arraySize - 1);
    }

    throw StateError('SparseTypeList is full (capacity $_arraySize)');
  }

  /// Remove a Type-ComponentId mapping
  void remove(final Type type) {
    var index = _getIndex(type);
    for (var probes = 0; probes < _arraySize; probes++) {
      final key = _keys[index];
      if (key == null) return;
      if (key == type) {
        _keys[index] = _tombstone;
        _values[index] = null;
        _length--;
        return;
      }
      index = (index + 1) & (_arraySize - 1);
    }
  }

  /// Calculate array index using fast modulo: hashCode & (size - 1)
  /// This is equivalent to hashCode.abs() % _arraySize but much faster
  int _getIndex(final Type type) => type.hashCode.abs() & (_arraySize - 1);
}
