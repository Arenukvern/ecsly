import 'dart:typed_data';

import '../columns/data_column.dart';
import 'simd_target.dart';

/// Utility functions for common SIMD operations.
class SimdUtils {
  SimdUtils._(); // Private constructor - static class

  /// Adds [a] and [b] component by component and stores the sum in [result].
  ///
  /// All three columns need the same stride and length. On the VM and in AOT
  /// whole `Float32x4` vectors are added. Fewer than four live floats, and
  /// every call on `dart2js`, DDC, and `dart2wasm`, use the scalar twin.
  static void addColumnsSimd(FloatColumn a, FloatColumn b, FloatColumn result) {
    assert(
      a.stride == b.stride && b.stride == result.stride,
      'Columns must have the same stride',
    );
    assert(
      a.length == b.length && b.length == result.length,
      'Columns must have the same length',
    );

    final aVectors = a.simdWindow.vectors;
    final bVectors = b.simdWindow.vectors;
    final resultVectors = result.simdWindow.vectors;
    final vectorised =
        kEcslySimdHardware &&
        aVectors.isNotEmpty &&
        aVectors.length == bVectors.length &&
        aVectors.length == resultVectors.length;
    if (!vectorised) {
      // Also the release path for mismatched lengths, which asserts reject.
      _addScalar(a, b, result, 0);
      return;
    }
    simdAddVectors(aVectors, bVectors, resultVectors);
    final covered = aVectors.length * 4;
    if (covered < a.length * a.stride) {
      _addScalar(a, b, result, covered);
    }
  }

  static void _addScalar(
    FloatColumn a,
    FloatColumn b,
    FloatColumn result,
    int startFloat,
  ) {
    final aData = a.data;
    final bData = b.data;
    final resultData = result.data;
    final end = a.length * a.stride;
    for (var i = startFloat; i < end; i++) {
      resultData[i] = aData[i] + bData[i];
    }
  }

  /// Dot product of each row of [a] with the same row of [b].
  ///
  /// Returns a new stride-1 column. Both columns need the same stride and
  /// length. On the VM and in AOT, stride 2 and stride 4 rows are multiplied
  /// as `Float32x4` lanes; other strides, and every call on `dart2js`, DDC,
  /// and `dart2wasm`, use the scalar twin, which sums in double precision.
  /// Vector rows round in float32 and can differ from the scalar twin.
  static FloatColumn dotProductSimd(FloatColumn a, FloatColumn b) {
    assert(a.stride == b.stride, 'Columns must have the same stride');
    assert(a.length == b.length, 'Columns must have the same length');

    final result = FloatColumn(stride: 1, initialCapacity: a.length);
    for (var i = 0; i < a.length; i++) {
      result.addBlank();
    }

    final dots = result.data;
    final aVectors = a.simdWindow.vectors;
    if (kEcslySimdHardware && aVectors.isNotEmpty) {
      final bVectors = b.simdWindow.vectors;
      if (a.stride == 2) {
        simdDotPairs(aVectors, bVectors, dots);
        final covered = aVectors.length * 2;
        _dotScalar(a, b, dots, covered, a.length);
        return result;
      }
      if (a.stride == 4) {
        simdDotRows(aVectors, bVectors, dots);
        return result;
      }
    }
    _dotScalar(a, b, dots, 0, a.length);
    return result;
  }

  static void _dotScalar(
    FloatColumn a,
    FloatColumn b,
    Float32List dots,
    int start,
    int end,
  ) {
    final stride = a.stride;
    final aData = a.data;
    final bData = b.data;
    for (
      var row = start, offset = start * stride;
      row < end;
      row++, offset += stride
    ) {
      var sum = 0.0;
      for (var lane = 0; lane < stride; lane++) {
        sum += aData[offset + lane] * bData[offset + lane];
      }
      dots[row] = sum;
    }
  }

  /// Multiplies every live component of [column] by [scalar], for any stride.
  ///
  /// On the VM and in AOT whole `Float32x4` vectors are scaled. Fewer than
  /// four live floats, and every call on `dart2js`, DDC, and `dart2wasm`, use
  /// the scalar twin. Vector rows use the float32 value of [scalar] and can
  /// differ from a double-precision product by an ulp.
  static void multiplyColumnSimd(FloatColumn column, double scalar) {
    final window = column.simdWindow;
    if (!kEcslySimdHardware || window.vectors.isEmpty) {
      _multiplyScalar(column, scalar, 0);
      return;
    }
    simdMultiplyVectors(window.vectors, scalar);
    if (window.tailFloats > 0) {
      // The tail keeps the float32 constant the vector lanes used.
      _multiplyScalar(column, simdFloat32(scalar), window.vectors.length * 4);
    }
  }

  static void _multiplyScalar(FloatColumn column, double scalar, int start) {
    final data = column.data;
    final end = column.length * column.stride;
    for (var i = start; i < end; i++) {
      data[i] = data[i] * scalar;
    }
  }
}
