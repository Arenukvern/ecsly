// ignore_for_file: do_not_use_environment

import 'dart:typed_data';

/// True when `Float32x4` lowers to hardware SIMD on this compile target.
///
/// True only on the VM and in AOT. `dart2js` and DDC emulate SIMD values.
/// `dart2wasm` since Dart 3.14 lowers them to Wasm v128 instructions, but
/// allocates a wrapper per operation and reaches `Float32List` storage
/// through a slow view, so its vector loops also run slower than plain
/// doubles. The package kernels use this to pick a scalar twin; user kernels
/// can do the same:
///
/// ```dart
/// if (kEcslySimdHardware) {
///   // Float32x4 loop over column.simdWindow
/// } else {
///   // double loop over column.data
/// }
/// ```
const bool kEcslySimdHardware =
    bool.fromEnvironment('dart.library.io') &&
    !bool.fromEnvironment('dart.tool.dart2wasm');

final _float32 = Float32List(1);

/// Rounds [value] to float32 without allocating.
double simdFloat32(double value) {
  _float32[0] = value;
  return _float32[0];
}

// The vector loops below live in small functions, each bounded by its own
// list length. The VM can then drop the bounds check; a loop bounded by a
// separate integer keeps it and measured slower in AOT. A short function also
// lets the optimizer unbox the vectors whatever the calling kernel looks like.
//
// The kernels pass doubles in and build the vectors here. A `Float32x4` built
// in the caller is boxed on the way in when the call is not inlined.

/// Multiplies every vector in place by the float32 value of [factor].
void simdMultiplyVectors(Float32x4List vectors, double factor) {
  final vector = Float32x4.splat(factor);
  for (var i = 0; i < vectors.length; i++) {
    vectors[i] = vectors[i] * vector;
  }
}

/// Stores `a[i] + b[i]` for every vector.
void simdAddVectors(Float32x4List a, Float32x4List b, Float32x4List sum) {
  for (var i = 0; i < a.length; i++) {
    sum[i] = a[i] + b[i];
  }
}

/// Stores `positions[i] + velocities[i] * dt` for every vector.
void simdIntegrateVectors(
  Float32x4List positions,
  Float32x4List velocities,
  double dt,
) {
  final step = Float32x4.splat(dt);
  for (var i = 0; i < positions.length; i++) {
    positions[i] = positions[i] + velocities[i] * step;
  }
}

/// Length of each xy pair in `[x0, y0, x1, y1]`, as `[m0, m0, m1, m1]`.
Float32x4 simdPairLength(Float32x4 vector) {
  final squared = vector * vector;
  return (squared + squared.shuffle(Float32x4.yxwz)).sqrt();
}

/// Stores the distance of each xy pair to `(targetX, targetY)`.
///
/// [positions] packs two rows per vector; [distances] gets one entry per pair
/// lane, so it needs two entries per vector.
void simdDistanceVectors(
  Float32x4List positions,
  double targetX,
  double targetY,
  Float32List distances,
) {
  final targetXy = Float32x4(targetX, targetY, targetX, targetY);
  for (var i = 0; i < positions.length; i++) {
    final magnitude = simdPairLength(positions[i] - targetXy);
    final row = i * 2;
    distances[row] = magnitude.x;
    distances[row + 1] = magnitude.z;
  }
}

/// Stores the dot product of each xy pair of rows.
void simdDotPairs(Float32x4List a, Float32x4List b, Float32List dots) {
  for (var i = 0; i < a.length; i++) {
    final product = a[i] * b[i];
    final pair = product + product.shuffle(Float32x4.yxwz);
    dots[i * 2] = pair.x;
    dots[i * 2 + 1] = pair.z;
  }
}

/// Stores the dot product of each four-lane row.
void simdDotRows(Float32x4List a, Float32x4List b, Float32List dots) {
  for (var i = 0; i < a.length; i++) {
    final product = a[i] * b[i];
    dots[i] = product.x + product.y + product.z + product.w;
  }
}
