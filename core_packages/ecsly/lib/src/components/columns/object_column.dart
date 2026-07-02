part of 'data_column.dart';

/// Column for storing complex object components (Inventory, AI State, etc.).
///
/// This is the "slow path" - uses heap-allocated objects.
/// Trade-off: Iterating ObjectColumn will trigger Cache Misses and GC.
/// Rule: Only use this for "Cold" data that isn't processed 60 times per second.
class ObjectColumn<T extends Object> implements DataColumn {
  ObjectColumn({final int initialCapacity = 8})
    : _data = List<T?>.filled(initialCapacity, null),
      _length = 0;

  List<T?> _data;
  int _length;

  @override
  int get capacity => _data.length;

  @override
  int get length => _length;

  @override
  void addBlank() {
    if (_length >= capacity) {
      resize(capacity * 2);
    }
    _data[_length] = null;
    _length++;
  }

  @override
  void clear() {
    for (int i = 0; i < _length; i++) {
      _data[i] = null;
    }
    _length = 0;
  }

  @override
  void copyTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  ) {
    assert(sourceIndex < _length, 'Source index out of bounds');
    if (destination is! ObjectColumn<T>) {
      throw ArgumentError('Destination must be ObjectColumn<$T>');
    }
    final dest = destination;
    dest._data[destIndex] = _data[sourceIndex];
  }

  /// Fill a range of indices with a value.
  ///
  /// Useful for batch operations like clearing ranges efficiently.
  void fillRange(final int start, final int end, final T? value) {
    for (int i = start; i < end; i++) {
      _data[i] = value;
    }
  }

  /// Get object at index.
  T? getValue(final int index) {
    assert(index < _length, 'Index out of bounds');
    return _data[index];
  }

  @override
  void moveTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  ) {
    copyTo(sourceIndex, destination, destIndex);
    _data[sourceIndex] = null;
  }

  @override
  void resize(final int newCapacity) {
    if (newCapacity <= capacity) return;
    final newData = List<T?>.filled(newCapacity, null);
    for (int i = 0; i < _length; i++) {
      newData[i] = _data[i];
    }
    _data = newData;
  }

  /// Set object at index.
  void setValue(final int index, final T? value) {
    assert(index < _length, 'Index out of bounds');
    _data[index] = value;
  }

  @override
  void swap(final int indexA, final int indexB) {
    assert(indexA < _length && indexB < _length, 'Indices out of bounds');
    if (indexA == indexB) return;
    final temp = _data[indexA];
    _data[indexA] = _data[indexB];
    _data[indexB] = temp;
  }

  @override
  void swapRemove(final int index) {
    assert(index < _length, 'Index out of bounds');
    if (index != _length - 1) {
      _data[index] = _data[_length - 1];
    }
    _data[_length - 1] = null;
    _length--;
  }
}
