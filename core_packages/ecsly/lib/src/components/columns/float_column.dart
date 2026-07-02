part of 'data_column.dart';

/// Column for storing float/double components (Position, Velocity, etc.).
///
/// Uses stride-based packing: [x0, y0, x1, y1, x2, y2, ...]
/// where stride is the number of floats per component (e.g., 2 for Position x,y).
final class FloatColumn extends DataColumn {
  FloatColumn({required this.stride, final int initialCapacity = 8})
    : _data = Float32List(initialCapacity * stride),
      _length = 0;
  static final FloatColumn zero = FloatColumn(stride: 0);

  Float32List _data;
  int _length;
  final int stride; // Elements per component (e.g., 2 for Position x,y)

  @override
  int get capacity => _data.length ~/ stride;

  /// Get raw Float32List view (for direct access).
  Float32List get data => _data;

  @override
  int get length => _length;

  /// Get SIMD view (Float32x4List) for vectorized operations.
  /// Note: Only works if stride is multiple of 4.
  Float32x4List? get simdView {
    if (stride % 4 != 0) return null;
    return _data.buffer.asFloat32x4List();
  }

  @override
  void addBlank() {
    if (_length >= capacity) {
      resize(capacity * 2); // Double capacity
    }
    // Zero-initialized by Float32List constructor
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
    if (destination is! FloatColumn) {
      throw ArgumentError('Destination must be FloatColumn');
    }
    if (destination.stride != stride) {
      throw ArgumentError('Stride mismatch');
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

  /// Get single float value at (index, componentIndex).
  /// Performs bounds checking for safety.
  double getValue(final int index, final int componentIndex) {
    final isNotStale = index < _length && componentIndex < stride;
    if (!isNotStale) return 0;
    assert(isNotStale, 'Index out of bounds');
    return _data[index * stride + componentIndex];
  }

  /// Get single float value at (index, componentIndex) without bounds checking.
  /// Use only when index and componentIndex are guaranteed to be valid.
  /// This is optimized for hot paths like query iterators where bounds are already validated.
  double getValueUnsafe(final int index, final int componentIndex) =>
      _data[index * stride + componentIndex];

  @override
  void moveTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  ) {
    copyTo(sourceIndex, destination, destIndex);
    // Clear source (set to zero)
    final sourceOffset = sourceIndex * stride;
    for (int i = 0; i < stride; i++) {
      _data[sourceOffset + i] = 0.0;
    }
  }

  @override
  void resize(final int newCapacity) {
    if (newCapacity <= capacity) return;

    final newData = Float32List(newCapacity * stride);
    newData.setRange(0, _data.length, _data);
    _data = newData;
  }

  /// Set element at index from Float32List.
  void set(final int index, final Float32List values) {
    assert(index < _length, 'Index out of bounds');
    assert(values.length == stride, 'Value length mismatch');
    final offset = index * stride;
    _data.setRange(offset, offset + stride, values);
  }

  /// Set single float value at (index, componentIndex).
  void setValue(final int index, final int componentIndex, final double value) {
    assert(index < _length && componentIndex < stride, 'Index out of bounds');
    _data[index * stride + componentIndex] = value;
  }

  @override
  void swap(final int indexA, final int indexB) {
    assert(indexA < _length && indexB < _length, 'Indices out of bounds');
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
  void swapRemove(final int index) {
    assert(index < _length, 'Index out of bounds');
    if (index != _length - 1) {
      swap(index, _length - 1);
    }
    _length--;
  }

  /// Get element at index as Float32List view.
  Float32List view(final int index) {
    assert(index < _length, 'Index out of bounds: $index >= $_length');
    final offset = index * stride;
    return _data.sublist(offset, offset + stride);
  }
}

/// SIMD-optimized operations for FloatColumn.
extension FloatColumnSimd on FloatColumn {
  /// Batch update using SIMD (processes 4 elements at a time).
  void batchSimdUpdate(final Float32x4 Function(int index) updateFn) {
    if (stride < 4) return;
    final simdData = _data.buffer.asFloat32x4List();
    final simdLength = (_length * stride) ~/ 4;

    for (int i = 0; i < simdLength; i++) {
      simdData[i] = updateFn(i);
    }
  }

  /// Get SIMD view for specific row range.
  /// Returns view starting at row index, with length elements.
  /// Returns null if stride is not multiple of 4 or range is invalid.
  Float32x4List? getSimdViewForRows(final int startRow, final int length) {
    if (stride % 4 != 0) return null;
    final startOffset = startRow * stride;
    final endOffset = startOffset + (length * stride);
    if (endOffset > _data.length || startRow < 0 || length < 0) return null;
    if (startRow + length > _length) return null;

    final buffer = _data.buffer.asByteData();
    final view = buffer.buffer.asFloat32x4List(
      startOffset ~/ 4,
      (length * stride) ~/ 4,
    );
    return view;
  }

  /// Vectorized add operation (4 components at once).
  /// Requires stride >= 4 and aligned access.
  void simdAdd(final int index, final Float32x4 delta) {
    if (stride < 4) return;
    final offset = index * stride;
    final simdData = _data.buffer.asFloat32x4List();
    final simdIndex = offset ~/ 4;
    simdData[simdIndex] = simdData[simdIndex] + delta;
  }

  /// Vectorized multiply operation.
  void simdMultiply(final int index, final Float32x4 factor) {
    if (stride < 4) return;
    final offset = index * stride;
    final simdData = _data.buffer.asFloat32x4List();
    final simdIndex = offset ~/ 4;
    simdData[simdIndex] = simdData[simdIndex] * factor;
  }

  /// Process column using SIMD (if available).
  /// Falls back to scalar processing if SIMD unavailable.
  void simdProcess(final Float32x4 Function(Float32x4) processor) {
    final simd = simdView;
    if (simd != null) {
      // Process all elements as SIMD vectors
      for (int i = 0; i < simd.length; i++) {
        simd[i] = processor(simd[i]);
      }
    } else {
      // Fallback to scalar
      _scalarProcess(processor);
    }
  }

  /// Scalar fallback for simdProcess.
  void _scalarProcess(final Float32x4 Function(Float32x4) processor) {
    for (int i = 0; i < _length; i++) {
      for (int j = 0; j < stride; j++) {
        final value = getValue(i, j);
        // Convert to SIMD, process, convert back
        final vec = Float32x4.splat(value);
        final result = processor(vec);
        setValue(i, j, result.x); // Use first component
      }
    }
  }
}
