import 'dart:math' as math;
import 'dart:typed_data';

import '../columns/data_column.dart';
import 'simd_target.dart';

/// Distance from every position to `(target.x, target.y)`.
///
/// [target] contributes `x` and `y` only. The shorter column bounds the rows
/// written. On the VM and in AOT two positions share one `Float32x4`; the
/// last odd position, and every position on `dart2js`, DDC, and `dart2wasm`,
/// goes through the scalar twin. Vector rows round in float32 and can differ
/// from the scalar twin by an ulp.
void calculateDistancesSimd(
  FloatColumn positionColumn,
  Float32x4 target,
  FloatColumn outputColumn,
) {
  assert(positionColumn.stride == 2, '(x, y) Column stride must be 2');
  assert(outputColumn.stride == 1, '(Distance) Output column stride must be 1');

  final count = positionColumn.length < outputColumn.length
      ? positionColumn.length
      : outputColumn.length;
  final positions = positionColumn.simdWindow.vectors;
  if (!kEcslySimdHardware ||
      positions.isEmpty ||
      count != positionColumn.length) {
    _distanceScalar(positionColumn, target.x, target.y, outputColumn, 0, count);
    return;
  }
  simdDistanceVectors(positions, target.x, target.y, outputColumn.data);
  final covered = positions.length * 2;
  if (covered < count) {
    // An odd position is the tail.
    _distanceScalar(
      positionColumn,
      target.x,
      target.y,
      outputColumn,
      covered,
      count,
    );
  }
}

void _distanceScalar(
  FloatColumn positionColumn,
  double targetX,
  double targetY,
  FloatColumn outputColumn,
  int start,
  int end,
) {
  final positions = positionColumn.data;
  final distances = outputColumn.data;
  for (var row = start, offset = start * 2; row < end; row++, offset += 2) {
    final dx = positions[offset] - targetX;
    final dy = positions[offset + 1] - targetY;
    distances[row] = math.sqrt(dx * dx + dy * dy);
  }
}

/// Scales each `(x, y)` to unit length.
///
/// A zero or NaN magnitude leaves the row unchanged. This kernel stays scalar
/// on every target: one vector square root and one vector divide per two rows
/// measured slower than this double loop in AOT on arm64. The result is
/// bit-identical on the VM, Wasm, `dart2js`, and DDC.
void normalizeVectorsSimd(FloatColumn vectorColumn) {
  assert(vectorColumn.stride == 2, '(x, y) Column stride must be 2');

  final vectors = vectorColumn.data;
  final end = vectorColumn.length * 2;
  for (var i = 0; i < end; i += 2) {
    final x = vectors[i];
    final y = vectors[i + 1];
    final magnitude = math.sqrt(x * x + y * y);
    if (magnitude > 0) {
      vectors[i] = x / magnitude;
      vectors[i + 1] = y / magnitude;
    }
  }
}

/// Multiplies every live component by [scale], for any stride.
///
/// On the VM and in AOT whole `Float32x4` vectors are scaled. Fewer than four
/// live floats, and every call on `dart2js`, DDC, and `dart2wasm`, use the
/// scalar twin. Vector rows use the float32 value of [scale] and can differ
/// from a double-precision product by an ulp. Spare capacity is untouched.
void scalePositionsSimd(FloatColumn positionColumn, double scale) {
  final window = positionColumn.simdWindow;
  if (!kEcslySimdHardware || window.vectors.isEmpty) {
    _scaleScalar(positionColumn, scale, 0);
    return;
  }
  simdMultiplyVectors(window.vectors, scale);
  if (window.tailFloats > 0) {
    // The tail keeps the float32 constant the vector lanes used.
    _scaleScalar(positionColumn, simdFloat32(scale), window.vectors.length * 4);
  }
}

void _scaleScalar(FloatColumn column, double scale, int startFloat) {
  final data = column.data;
  final end = column.length * column.stride;
  for (var i = startFloat; i < end; i++) {
    data[i] = data[i] * scale;
  }
}

/// Integrates positions: `position += velocity * dt`.
///
/// Both columns are stride 2 and the shorter one bounds the rows updated. On
/// the VM and in AOT one `Float32x4` holds `[x0, y0, x1, y1]` for two rows.
/// The last odd row, and every row on `dart2js`, DDC, and `dart2wasm`, goes
/// through the scalar twin. Vector rows round in float32 and can differ from
/// it by an ulp.
void updatePositionSimd(
  FloatColumn positionColumn,
  FloatColumn velocityColumn,
  double dt,
) {
  assert(positionColumn.stride == 2, '(x, y) Column stride must be 2');
  assert(velocityColumn.stride == 2, '(dx, dy) Column stride must be 2');

  final count = positionColumn.length < velocityColumn.length
      ? positionColumn.length
      : velocityColumn.length;
  final positions = positionColumn.simdWindow.vectors;
  if (!kEcslySimdHardware ||
      positions.isEmpty ||
      count != positionColumn.length) {
    _integrateScalar(positionColumn, velocityColumn, dt, 0, count);
    return;
  }
  simdIntegrateVectors(positions, velocityColumn.simdWindow.vectors, dt);
  final covered = positions.length * 2;
  if (covered < count) {
    // An odd position is the tail.
    _integrateScalar(positionColumn, velocityColumn, dt, covered, count);
  }
}

void _integrateScalar(
  FloatColumn positionColumn,
  FloatColumn velocityColumn,
  double dt,
  int start,
  int end,
) {
  final positions = positionColumn.data;
  final velocities = velocityColumn.data;
  for (var row = start, offset = start * 2; row < end; row++, offset += 2) {
    positions[offset] = positions[offset] + velocities[offset] * dt;
    positions[offset + 1] = positions[offset + 1] + velocities[offset + 1] * dt;
  }
}
