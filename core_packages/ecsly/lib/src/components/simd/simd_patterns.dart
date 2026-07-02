// ignore_for_file: cascade_invocations

import 'dart:math' as math;
import 'dart:typed_data';

import '../columns/data_column.dart';

/// Calculate distances between positions (SIMD-optimized).
void calculateDistancesSimd(
  final FloatColumn positionColumn,
  final Float32x4 target,
  final FloatColumn outputColumn,
) {
  assert(positionColumn.stride == 2, '(x, y) Column stride must be 2');
  assert(outputColumn.stride == 1, '(Distance) Output column stride must be 1');

  final posSimd = positionColumn.simdView;

  if (posSimd != null) {
    // Process 2 positions at a time
    for (int i = 0; i < posSimd.length; i++) {
      final pos = posSimd[i];

      // Extract x, y pairs (Float32x2 doesn't exist, work with components directly)
      // pos contains [x1, y1, x2, y2], target contains [tx1, ty1, tx2, ty2]
      // Calculate distances for both pairs
      final dx1 = pos.x - target.x;
      final dy1 = pos.y - target.y;
      final dx2 = pos.z - target.z;
      final dy2 = pos.w - target.w;
      final dist1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
      final dist2 = math.sqrt(dx2 * dx2 + dy2 * dy2);

      // Store distances
      final rowIndex1 = i * 2;
      final rowIndex2 = i * 2 + 1;
      if (rowIndex1 < outputColumn.length) {
        outputColumn.setValue(rowIndex1, 0, dist1);
      }
      if (rowIndex2 < outputColumn.length) {
        outputColumn.setValue(rowIndex2, 0, dist2);
      }
    }
  } else {
    // Scalar fallback
    for (int i = 0; i < positionColumn.length; i++) {
      final x = positionColumn.getValue(i, 0);
      final y = positionColumn.getValue(i, 1);
      final dx = x - target.x;
      final dy = y - target.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      outputColumn.setValue(i, 0, distance);
    }
  }
}

/// Normalize a batch of vectors (SIMD-optimized).
void normalizeVectorsSimd(final FloatColumn vectorColumn) {
  assert(vectorColumn.stride == 2, '(x, y) Column stride must be 2');

  final simd = vectorColumn.simdView;

  if (simd != null) {
    for (int i = 0; i < simd.length; i++) {
      final vec = simd[i];

      // Calculate magnitude for each vector pair
      // vec contains [x1, y1, x2, y2]
      final x1 = vec.x;
      final y1 = vec.y;
      final x2 = vec.z;
      final y2 = vec.w;

      // Magnitude: sqrt(x^2 + y^2)
      final mag1 = math.sqrt(x1 * x1 + y1 * y1);
      final mag2 = math.sqrt(x2 * x2 + y2 * y2);

      // Normalize: vec / mag
      final norm1x = mag1 > 0 ? x1 / mag1 : 0.0;
      final norm1y = mag1 > 0 ? y1 / mag1 : 0.0;
      final norm2x = mag2 > 0 ? x2 / mag2 : 0.0;
      final norm2y = mag2 > 0 ? y2 / mag2 : 0.0;

      // Store normalized vectors
      simd[i] = Float32x4(norm1x, norm1y, norm2x, norm2y);
    }
  } else {
    // Scalar fallback
    for (int i = 0; i < vectorColumn.length; i++) {
      final x = vectorColumn.getValue(i, 0);
      final y = vectorColumn.getValue(i, 1);
      final mag = math.sqrt(x * x + y * y);
      if (mag > 0) {
        vectorColumn.setValue(i, 0, x / mag);
        vectorColumn.setValue(i, 1, y / mag);
      }
    }
  }
}

/// Scale all Position components by a factor.
void scalePositionsSimd(final FloatColumn positionColumn, final double scale) {
  final simd = positionColumn.simdView;
  final scaleVec = Float32x4.splat(scale);

  if (simd != null) {
    for (int i = 0; i < simd.length; i++) {
      simd[i] = simd[i] * scaleVec;
    }
  } else {
    // Scalar fallback
    for (int i = 0; i < positionColumn.length; i++) {
      for (int j = 0; j < positionColumn.stride; j++) {
        final value = positionColumn.getValue(i, j);
        positionColumn.setValue(i, j, value * scale);
      }
    }
  }
}

/// Update Position components using Velocity (SIMD-optimized).
void updatePositionSimd(
  final FloatColumn positionColumn,
  final FloatColumn velocityColumn,
  final double dt,
) {
  assert(positionColumn.stride == 2, '(x, y) Column stride must be 2');
  assert(velocityColumn.stride == 2, '(dx, dy) Column stride must be 2');

  final posSimd = positionColumn.simdView;
  final velSimd = velocityColumn.simdView;

  if (posSimd != null && velSimd != null) {
    // Process 2 positions at a time (4 floats = 2 positions)
    final dtVec = Float32x4.splat(dt);

    for (int i = 0; i < posSimd.length && i < velSimd.length; i++) {
      // Load position and velocity
      final pos = posSimd[i];
      final vel = velSimd[i];

      // Compute: pos = pos + vel * dt
      posSimd[i] = pos + (vel * dtVec);
    }
  } else {
    // Scalar fallback
    for (int i = 0; i < positionColumn.length; i++) {
      final x = positionColumn.getValue(i, 0);
      final y = positionColumn.getValue(i, 1);
      final dx = velocityColumn.getValue(i, 0);
      final dy = velocityColumn.getValue(i, 1);

      positionColumn.setValue(i, 0, x + dx * dt);
      positionColumn.setValue(i, 1, y + dy * dt);
    }
  }
}
