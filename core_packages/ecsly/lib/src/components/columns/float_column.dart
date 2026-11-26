part of 'data_column.dart';

/// Column for storing float/double components (Position, Velocity, etc.).
///
/// Uses stride-based packing: [x0, y0, x1, y1, x2, y2, ...]
/// where stride is the number of floats per component (e.g., 2 for Position x,y).
final class FloatColumn extends DataColumn {
  FloatColumn({required this.stride, int initialCapacity = 8})
    : _data = Float32List(initialCapacity * stride),
      _length = 0;
  static final FloatColumn zero = FloatColumn(stride: 0);

  Float32List _data;
  int _length;
  final int stride; // Elements per component (e.g., 2 for Position x,y)

  /// The last [simdWindow] handed out, and the [_length] it was built for.
  SimdFloatWindow? _window;
  int _windowLength = -1;

  @override
  int get capacity => _data.length ~/ stride;

  /// Get raw Float32List view (for direct access).
  Float32List get data => _data;

  @override
  int get length => _length;

  /// Live `Float32x4List` for a stride that is a multiple of 4.
  ///
  /// Null for any other stride; stride-2 columns use [simdWindow]. The view
  /// stops at the live rows and leaves spare capacity out. It is the vector
  /// list of [simdWindow] and follows the same reuse.
  Float32x4List? get simdView {
    if (stride % 4 != 0) return null;
    return simdWindow.vectors;
  }

  /// Live `Float32x4` prefix for any stride, plus a 0–3 float tail.
  ///
  /// A stride-2 column packs `[x0, y0, x1, y1]` into one vector. The tail is
  /// the live floats that do not fill a vector. Spare capacity is never part
  /// of a window.
  ///
  /// The window is a view over this column, not a copy. It is rebuilt when
  /// [length] changes, so a system that takes it every frame on a stable
  /// column does not allocate. Take it again after [resize]: an older window
  /// then still views the previous buffer.
  SimdFloatWindow get simdWindow {
    final cached = _window;
    if (cached != null && _windowLength == _length) return cached;
    final liveFloats = _length * stride;
    final vectorCount = liveFloats ~/ 4;
    final window = SimdFloatWindow(
      _data.buffer.asFloat32x4List(0, vectorCount),
      liveFloats - vectorCount * 4,
    );
    _window = window;
    _windowLength = _length;
    return window;
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
  void copyTo(int sourceIndex, DataColumn destination, int destIndex) {
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
  double getValue(int index, int componentIndex) {
    final isNotStale = index < _length && componentIndex < stride;
    if (!isNotStale) return 0;
    assert(isNotStale, 'Index out of bounds');
    return _data[index * stride + componentIndex];
  }

  /// Get single float value at (index, componentIndex) without bounds checking.
  /// Use only when index and componentIndex are guaranteed to be valid.
  /// This is optimized for hot paths like query iterators where bounds are already validated.
  double getValueUnsafe(int index, int componentIndex) =>
      _data[index * stride + componentIndex];

  @override
  void moveTo(int sourceIndex, DataColumn destination, int destIndex) {
    copyTo(sourceIndex, destination, destIndex);
    // Clear source (set to zero)
    final sourceOffset = sourceIndex * stride;
    for (int i = 0; i < stride; i++) {
      _data[sourceOffset + i] = 0.0;
    }
  }

  @override
  void resize(int newCapacity) {
    if (newCapacity <= capacity) return;

    final newData = Float32List(newCapacity * stride);
    newData.setRange(0, _data.length, _data);
    _data = newData;
    _window = null;
  }

  /// Set element at index from Float32List.
  void set(int index, Float32List values) {
    assert(index < _length, 'Index out of bounds');
    assert(values.length == stride, 'Value length mismatch');
    final offset = index * stride;
    _data.setRange(offset, offset + stride, values);
  }

  /// Set single float value at (index, componentIndex).
  void setValue(int index, int componentIndex, double value) {
    assert(index < _length && componentIndex < stride, 'Index out of bounds');
    _data[index * stride + componentIndex] = value;
  }

  @override
  void swap(int indexA, int indexB) {
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
  void swapRemove(int index) {
    assert(index < _length, 'Index out of bounds');
    if (index != _length - 1) {
      swap(index, _length - 1);
    }
    _length--;
  }

  /// Get element at index as Float32List view.
  Float32List view(int index) {
    assert(index < _length, 'Index out of bounds: $index >= $_length');
    final offset = index * stride;
    return _data.sublist(offset, offset + stride);
  }
}

/// Live `Float32x4` prefix of a [FloatColumn], plus the unfilled tail.
final class SimdFloatWindow {
  const SimdFloatWindow(this.vectors, this.tailFloats);

  /// Live floats grouped by four. Empty when fewer than four live floats.
  final Float32x4List vectors;

  /// Live floats after [vectors]. Always 0, 1, 2, or 3.
  final int tailFloats;
}

/// SIMD-optimized operations for FloatColumn.
extension FloatColumnSimd on FloatColumn {
  /// Writes [updateFn] over each live `Float32x4`.
  ///
  /// [updateFn] receives the vector index, which is the row index when
  /// [stride] is 4. A no-op when [stride] is not a multiple of 4, because a
  /// vector would then cover parts of two rows. Spare capacity is untouched.
  void batchSimdUpdate(Float32x4 Function(int index) updateFn) {
    if (stride % 4 != 0) return;
    final vectorCount = (_length * stride) ~/ 4;
    if (vectorCount == 0) return;
    final simdData = _data.buffer.asFloat32x4List();
    for (int i = 0; i < vectorCount; i++) {
      simdData[i] = updateFn(i);
    }
  }

  /// Live `Float32x4List` over [length] rows starting at [startRow].
  ///
  /// Returns null when the span leaves the live rows, or when the start float
  /// or the span is not a whole number of 16-byte vectors. A stride-2 column
  /// therefore needs an even [startRow] and an even [length].
  Float32x4List? getSimdViewForRows(int startRow, int length) {
    if (startRow < 0 || length < 0) return null;
    if (startRow + length > _length) return null;
    final startFloat = startRow * stride;
    final spanFloats = length * stride;
    if (startFloat % 4 != 0 || spanFloats % 4 != 0) return null;

    return _data.buffer.asFloat32x4List(startFloat * 4, spanFloats ~/ 4);
  }

  /// Adds [delta] to row [index], component by component.
  ///
  /// Component `j` of the row receives lane `j % 4`, so a stride-2 row gets
  /// `delta.x` and `delta.y`. A stride-4 row is one vector op; other strides
  /// add per component with the same float32 result. An out-of-range row is
  /// ignored.
  void simdAdd(int index, Float32x4 delta) {
    if (index < 0 || index >= _length) return;
    if (stride == 4) {
      final vectors = simdWindow.vectors;
      vectors[index] = vectors[index] + delta;
      return;
    }
    final offset = index * stride;
    for (var lane = 0; lane < stride; lane++) {
      _data[offset + lane] += _lane(delta, lane);
    }
  }

  /// Multiplies row [index] by [factor], component by component.
  ///
  /// Follows the same lane rule as [simdAdd]. An out-of-range row is ignored.
  void simdMultiply(int index, Float32x4 factor) {
    if (index < 0 || index >= _length) return;
    if (stride == 4) {
      final vectors = simdWindow.vectors;
      vectors[index] = vectors[index] * factor;
      return;
    }
    final offset = index * stride;
    for (var lane = 0; lane < stride; lane++) {
      _data[offset + lane] *= _lane(factor, lane);
    }
  }

  /// Applies [processor] to each live vector of a stride that is a multiple
  /// of 4.
  ///
  /// Spare capacity is untouched. Any other stride runs the per-float fallback,
  /// which calls [processor] on a splat of each component and stores lane `x`.
  void simdProcess(Float32x4 Function(Float32x4) processor) {
    final liveFloats = _length * stride;
    final vectorCount = liveFloats ~/ 4;
    if (stride % 4 == 0 && vectorCount > 0) {
      final simd = _data.buffer.asFloat32x4List(0, vectorCount);
      for (int i = 0; i < simd.length; i++) {
        simd[i] = processor(simd[i]);
      }
      return;
    }
    _scalarProcess(processor);
  }

  /// Scalar fallback for simdProcess.
  void _scalarProcess(Float32x4 Function(Float32x4) processor) {
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

double _lane(Float32x4 vector, int lane) => switch (lane & 3) {
  0 => vector.x,
  1 => vector.y,
  2 => vector.z,
  _ => vector.w,
};
