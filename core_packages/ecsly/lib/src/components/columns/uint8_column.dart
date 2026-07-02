// ignore_for_file: cascade_invocations

part of 'data_column.dart';

/// Column for storing small integer components (0-255 range).
///
/// Uses Uint8List for 4x memory reduction compared to Int32List.
/// Ideal for Health, Team IDs, enum values, and other small integers.
class Uint8Column implements DataColumn {
  Uint8Column({final int initialCapacity = 8})
    : _data = Uint8List(initialCapacity),
      _length = 0;

  Uint8List _data;
  int _length;

  @override
  int get capacity => _data.length;

  Uint8List get data => _data;

  @override
  int get length => _length;

  @override
  void addBlank() {
    if (_length >= capacity) {
      resize(capacity * 2);
    }
    _data[_length] = 0;
    _length++;
  }

  @override
  void clear() {
    _length = 0;
  }

  @override
  void copyTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  ) {
    assert(sourceIndex < _length, 'Source index out of bounds');
    if (destination is! Uint8Column) {
      throw ArgumentError('Destination must be Uint8Column');
    }
    destination._data[destIndex] = _data[sourceIndex];
  }

  /// Get value at index.
  int getValue(final int index) {
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
    _data[sourceIndex] = 0;
  }

  @override
  void resize(final int newCapacity) {
    if (newCapacity <= capacity) return;
    final newData = Uint8List(newCapacity);
    newData.setRange(0, _data.length, _data);
    _data = newData;
  }

  /// Set value at index.
  /// Values are clamped to 0-255 range (Uint8 limits).
  void setValue(final int index, final int value) {
    assert(index < _length, 'Index out of bounds');
    _data[index] = value.clamp(0, 255);
  }

  @override
  void swap(final int indexA, final int indexB) {
    assert(indexA < _length && indexB < _length, 'Indices out of bounds');
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
    _length--;
  }
}
