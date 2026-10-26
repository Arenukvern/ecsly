import 'dart:typed_data';

import 'package:test/test.dart';

/// Test harness for async_parallel package.
///
/// Provides utilities for testing isolate communication, buffer management,
/// and concurrent execution patterns.
class IsolatesTestHarness {
  IsolatesTestHarness._();

  /// Creates collision bounds data for broad phase testing.
  ///
  /// Returns Float32List with AABB bounds (minX, minY, maxX, maxY) per entity.
  static Float32List createCollisionBounds(final int entityCount) {
    final bounds = Float32List(entityCount * 4);
    for (int i = 0; i < entityCount; i++) {
      final x = i * 20.0;
      final y = i * 15.0;
      bounds[i * 4] = x; // minX
      bounds[i * 4 + 1] = y; // minY
      bounds[i * 4 + 2] = x + 10; // maxX
      bounds[i * 4 + 3] = y + 10; // maxY
    }
    return bounds;
  }

  /// Creates physics constraint data for solver testing.
  ///
  /// Returns maps with constraint parameters and current state.
  static Map<String, TypedData> createConstraintData(
    final int constraintCount,
  ) {
    final entityPairs = Int32List(constraintCount * 2);
    final constraintParams = Float32List(
      constraintCount * 3,
    ); // restLength, stiffness, damping
    final positions = Float32List(
      constraintCount * 4,
    ); // entityA pos + entityB pos
    final velocities = Float32List(
      constraintCount * 4,
    ); // entityA vel + entityB vel

    for (int i = 0; i < constraintCount; i++) {
      entityPairs[i * 2] = i * 2; // entity A
      entityPairs[i * 2 + 1] = i * 2 + 1; // entity B

      constraintParams[i * 3] = 50.0; // rest length
      constraintParams[i * 3 + 1] = 0.8; // stiffness
      constraintParams[i * 3 + 2] = 0.1; // damping

      // Entity A position
      positions[i * 4] = i * 30.0;
      positions[i * 4 + 1] = i * 20.0;
      // Entity B position
      positions[i * 4 + 2] = i * 30.0 + 60.0;
      positions[i * 4 + 3] = i * 20.0;
    }

    return {
      'entityPairs': entityPairs,
      'constraintParams': constraintParams,
      'positions': positions,
      'velocities': velocities,
    };
  }

  /// Creates test data buffers for algorithm testing.
  ///
  /// Returns a map with pre-filled TypedData buffers simulating ECS component data.
  static Map<String, TypedData> createTestBuffers({
    final int entityCount = 100,
    final bool includePositions = true,
    final bool includeVelocities = true,
    final bool includeMasses = false,
  }) {
    final buffers = <String, TypedData>{};

    if (includePositions) {
      // Create position data (x,y) for each entity
      final positions = Float32List(entityCount * 2);
      for (int i = 0; i < entityCount; i++) {
        positions[i * 2] = i * 10.0; // x
        positions[i * 2 + 1] = i * 5.0; // y
      }
      buffers['positions'] = positions;
    }

    if (includeVelocities) {
      // Create velocity data (dx,dy) for each entity
      final velocities = Float32List(entityCount * 2);
      for (int i = 0; i < entityCount; i++) {
        velocities[i * 2] = i * 0.1; // dx
        velocities[i * 2 + 1] = i * 0.05; // dy
      }
      buffers['velocities'] = velocities;
    }

    if (includeMasses) {
      // Create mass data for each entity
      final masses = Float32List(entityCount);
      for (int i = 0; i < entityCount; i++) {
        masses[i] = 1.0 + i * 0.1; // mass
      }
      buffers['masses'] = masses;
    }

    return buffers;
  }

  /// Measures execution time of an asynchronous operation.
  ///
  /// Useful for isolate communication performance testing.
  static Future<Duration> measureAsyncExecutionTime(
    final Future<void> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    await operation();
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// Measures execution time of a synchronous operation.
  ///
  /// Useful for performance regression testing.
  static Duration measureExecutionTime(final void Function() operation) {
    final stopwatch = Stopwatch()..start();
    operation();
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// Validates that TypedData buffers contain expected SIMD-compatible layouts.
  ///
  /// Checks alignment and stride requirements for vectorization.
  static void validateSimdCompatibility(
    final TypedData buffer,
    final int expectedStride,
  ) {
    expect(
      buffer.lengthInBytes % (expectedStride * 4),
      equals(0),
      reason: 'Buffer must be SIMD-compatible (multiple of stride * 4 bytes)',
    );
  }
}
