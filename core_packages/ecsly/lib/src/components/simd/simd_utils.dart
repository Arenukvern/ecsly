import 'dart:typed_data';

import '../columns/data_column.dart';

/// Utility functions for common SIMD operations.
class SimdUtils {
  SimdUtils._(); // Private constructor - static class

  /// Add two FloatColumns element-wise (SIMD).
  /// Requires all columns to have same stride and length.
  static void addColumnsSimd(
    final FloatColumn a,
    final FloatColumn b,
    final FloatColumn result,
  ) {
    assert(
      a.stride == b.stride && b.stride == result.stride,
      'Columns must have the same stride',
    );
    assert(
      a.length == b.length && b.length == result.length,
      'Columns must have the same length',
    );

    final aSimd = a.simdView;
    final bSimd = b.simdView;
    final resultSimd = result.simdView;

    if (aSimd != null && bSimd != null && resultSimd != null) {
      for (int i = 0; i < aSimd.length; i++) {
        resultSimd[i] = aSimd[i] + bSimd[i];
      }
    } else {
      // Scalar fallback
      for (int i = 0; i < a.length; i++) {
        for (int j = 0; j < a.stride; j++) {
          final sum = a.getValue(i, j) + b.getValue(i, j);
          result.setValue(i, j, sum);
        }
      }
    }
  }

  /// Dot product of two FloatColumns (SIMD).
  /// Returns a new FloatColumn with stride 1 containing dot products.
  /// Requires both columns to have same stride and length.
  static FloatColumn dotProductSimd(final FloatColumn a, final FloatColumn b) {
    assert(a.stride == b.stride, 'Columns must have the same stride');
    assert(a.length == b.length, 'Columns must have the same length');

    final result = FloatColumn(stride: 1, initialCapacity: a.length);

    // Resize result to match input length
    while (result.capacity < a.length) {
      result.resize(result.capacity * 2);
    }
    for (int i = 0; i < a.length; i++) {
      result.addBlank();
    }

    final aSimd = a.simdView;
    final bSimd = b.simdView;

    if (aSimd != null && bSimd != null) {
      // Process pairs of elements
      // Simplified: works best when stride is 4 (one row per SIMD vector)
      // For other strides, falls back to per-row calculation
      final simdLength = (a.length * a.stride) ~/ 4;
      for (int i = 0; i < simdLength; i++) {
        final aVec = aSimd[i];
        final bVec = bSimd[i];

        // Dot product: a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
        final product = aVec * bVec;
        final sum = product.x + product.y + product.z + product.w;

        // Store result (simplified - actual implementation depends on stride)
        // For stride 4, each SIMD vector represents one row
        if (a.stride == 4 && i < a.length) {
          result.setValue(i, 0, sum);
        } else {
          // For other strides, need to calculate per-row dot products
          // This is a simplified example - would need stride-specific handling
          // For now, fall back to scalar for non-4 strides
          break; // Will fall through to scalar fallback
        }
      }

      // If we didn't process all rows with SIMD, use scalar fallback for remainder
      if (a.stride != 4) {
        // Scalar fallback for non-4 strides
        for (int i = 0; i < a.length; i++) {
          double sum = 0;
          for (int j = 0; j < a.stride; j++) {
            sum += a.getValue(i, j) * b.getValue(i, j);
          }
          result.setValue(i, 0, sum);
        }
      }
    } else {
      // Scalar fallback
      for (int i = 0; i < a.length; i++) {
        double sum = 0;
        for (int j = 0; j < a.stride; j++) {
          sum += a.getValue(i, j) * b.getValue(i, j);
        }
        result.setValue(i, 0, sum);
      }
    }

    return result;
  }

  /// Multiply FloatColumn by scalar (SIMD).
  static void multiplyColumnSimd(
    final FloatColumn column,
    final double scalar,
  ) {
    final simd = column.simdView;
    final scalarVec = Float32x4.splat(scalar);

    if (simd != null) {
      for (int i = 0; i < simd.length; i++) {
        simd[i] = simd[i] * scalarVec;
      }
    } else {
      // Scalar fallback
      for (int i = 0; i < column.length; i++) {
        for (int j = 0; j < column.stride; j++) {
          column.setValue(i, j, column.getValue(i, j) * scalar);
        }
      }
    }
  }
}
