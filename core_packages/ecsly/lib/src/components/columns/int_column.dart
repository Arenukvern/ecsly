part of 'data_column.dart';

/// Live `Int32x4` prefix of an [IntColumn], plus the unfilled tail.
final class SimdIntWindow {
  const SimdIntWindow(this.vectors, this.tailInts);

  /// Live ints grouped by four. Empty when fewer than four live ints.
  final Int32x4List vectors;

  /// Live ints after [vectors]. Always 0, 1, 2, or 3.
  final int tailInts;
}

/// Column for storing integer components (Health, Team, etc.).
///
/// Uses stride-based packing: [x0, y0, x1, y1, x2, y2, ...]
/// where stride is the number of ints per component.
class IntColumn implements DataColumn {
  IntColumn({int initialCapacity = 8, this.stride = 1})
    : _data = Int32List(initialCapacity * stride),
      _length = 0;

  Int32List _data;
  int _length;
  final int stride;

  /// The last [simdWindow] handed out, and the [_length] it was built for.
  SimdIntWindow? _window;
  int _windowLength = -1;

  @override
  int get capacity => _data.length ~/ stride;

  Int32List get data => _data;

  /// Live `Int32x4` prefix for any stride, plus a 0–3 int tail.
  ///
  /// Spare capacity is excluded. The view is 16-byte aligned because the
  /// column owns its [Int32List]. Like [FloatColumn.simdWindow], it is a
  /// reused view that is rebuilt when [length] or the buffer changes.
  SimdIntWindow get simdWindow {
    final cached = _window;
    if (cached != null && _windowLength == _length) return cached;
    final liveInts = _length * stride;
    final vectorCount = liveInts ~/ 4;
    final window = SimdIntWindow(
      _data.buffer.asInt32x4List(0, vectorCount),
      liveInts - vectorCount * 4,
    );
    _window = window;
    _windowLength = _length;
    return window;
  }

  @override
  int get length => _length;

  @override
  void addBlank() {
    if (_length >= capacity) {
      resize(capacity * 2);
    }
    // Zero-initialize all components in the stride
    final offset = _length * stride;
    for (int i = 0; i < stride; i++) {
      _data[offset + i] = 0;
    }
    _length++;
  }

  @override
  void clear() {
    _length = 0;
  }

  @override
  void copyTo(int sourceIndex, DataColumn destination, int destIndex) {
    assert(sourceIndex < _length, 'Source index out of bounds');
    if (destination is! IntColumn) {
      throw ArgumentError('Destination must be IntColumn');
    }
    if (destination.stride != stride) {
      throw ArgumentError(
        'Stride mismatch: source=$stride, destination=${destination.stride}',
      );
    }

    final sourceOffset = sourceIndex * stride;
    final destOffset = destIndex * destination.stride;
    destination._data.setRange(
      destOffset,
      destOffset + stride,
      _data,
      sourceOffset,
    );
  }

  /// Get single int value at (index, componentIndex).
  /// Performs bounds checking for safety.
  int getValue(int index, int componentIndex) {
    final isNotStale = index < _length && componentIndex < stride;
    if (!isNotStale) return 0;
    assert(isNotStale, 'Index out of bounds');
    return _data[index * stride + componentIndex];
  }

  /// Get value at index (stride=1 only).
  /// Use [getValue(index, componentIndex)] for stride support.
  int getValueAt(int index) {
    assert(
      index < _length && stride == 1,
      'getValueAt only works with stride=1',
    );
    return _data[index];
  }

  @override
  void moveTo(int sourceIndex, DataColumn destination, int destIndex) {
    copyTo(sourceIndex, destination, destIndex);
    // Clear source (set to zero)
    final sourceOffset = sourceIndex * stride;
    for (int i = 0; i < stride; i++) {
      _data[sourceOffset + i] = 0;
    }
  }

  @override
  void resize(int newCapacity) {
    if (newCapacity <= capacity) return;
    final newData = Int32List(newCapacity * stride);
    newData.setRange(0, _data.length, _data);
    _data = newData;
    _window = null;
  }

  /// Set single int value at (index, componentIndex).
  void setValue(int index, int componentIndex, int value) {
    assert(index < _length && componentIndex < stride, 'Index out of bounds');
    _data[index * stride + componentIndex] = value;
  }

  /// Set value at index (backward compatibility for stride=1).
  /// Use [setValue(index, componentIndex, value)] for stride support.
  void setValueAt(int index, int value) {
    assert(
      index < _length && stride == 1,
      'setValueAt only works with stride=1. Use setValue(index, componentIndex, value) for multi-field support.',
    );
    _data[index] = value;
  }

  @override
  void swap(int indexA, int indexB) {
    assert(indexA < _length && indexB < _length, 'Index out of bounds');
    if (indexA == indexB) return;

    final offsetA = indexA * stride;
    final offsetB = indexB * stride;

    // Swap stride elements
    for (int i = 0; i < stride; i++) {
      final temp = _data[offsetA + i];
      _data[offsetA + i] = _data[offsetB + i];
      _data[offsetB + i] = temp;
    }
  }

  @override
  void swapRemove(int index) {
    assert(index < _length, 'Index out of bounds');
    if (index != _length - 1) {
      swap(index, _length - 1);
    }
    _length--;
  }
}
