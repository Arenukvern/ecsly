# Game Isolates: Zero-Cost Isolate Management

**Zero-cost isolate management for high-performance Dart applications.**

Provides TransferableTypedData double buffering and malloc.allocate shared memory abstractions for concurrent computing without GC pressure.

## Core Principles

- **Zero-Cost**: Minimal abstraction overhead, direct TypedData operations
- **Double Buffering**: Automatic ownership transfer between isolates
- **Shared Memory**: Optional malloc.allocate for zero-latency access
- **SIMD-Friendly**: Preserves TypedData layout across isolate boundaries

## Usage

### Double Buffering (Primary Strategy)

```dart
import 'lib/async_parallel.dart';

// Create isolate manager
final isolateManager = IsolateManager(_computeFunction);

// Start with 64KB buffer
await isolateManager.start(64 * 1024);

// Send input for computation
isolateManager.computeFrame(playerInput);

// Read results (safe from main isolate)
final renderData = isolateManager.renderBuffer?.asFloat32List();

// Cleanup
await isolateManager.shutdown();
```

### Shared Memory (Supplemental)

```dart
// Create shared memory (if available)
final sharedMem = SharedMemory.create(1024);
if (sharedMem != null) {
  // Share address with compute isolate
  isolate.send(sharedMem.address);

  // Access directly (requires synchronization)
  final data = sharedMem.asFloat32List();
  // ... use data ...

  sharedMem.free();
}
```

## Architecture

### TransferableTypedData Strategy

- **Zero-copy**: No data duplication during transfer
- **SIMD preservation**: Maintains TypedData layout across isolates
- **One-frame latency**: Standard trade-off for concurrent processing

### Double Buffer Pattern

```
Frame N:   Main (Render) ← Buffer A    Compute (Write) → Buffer B
Frame N+1: Main (Render) ← Buffer B    Compute (Write) → Buffer A
```

### Shared Memory Strategy

- **Zero-latency**: Real-time access from both isolates
- **Single buffer**: No memory duplication
- **Synchronization required**: Manual mutex/atomic coordination

## When to Use

### Use Double Buffering For:

- Primary ECS world state (positions, velocities, components)
- SIMD-heavy computations
- Frame-based updates

### Use Shared Memory For:

- Read-only static data (collision meshes, navigation graphs)
- Frequently accessed constants
- Low-frequency updates with zero-latency requirements

## Performance Characteristics

| Strategy      | Memory | Latency  | GC Pressure | Synchronization |
| ------------- | ------ | -------- | ----------- | --------------- |
| Double Buffer | 2x     | 1 frame  | None        | Automatic       |
| Shared Memory | 1x     | 0 frames | Low         | Manual          |

## Platform Support

- **Double Buffering**: All Dart platforms
- **Shared Memory**: Limited (dart:ffi dependent)

## Integration with Game Algorithms

This package is designed to work alongside `game_algorithms` for ECS physics:

```dart
// game_algorithms focuses on pure algorithms
class SIMDPhysicsStepper {
  void step(Float32List positions, Float32List velocities, double dt) {
    // Pure SIMD physics computation
  }
}

// async_parallel handles concurrent execution
void computeIsolate(_ComputeIsolateArgs args) {
  final stepper = SIMDPhysicsStepper();
  final buffer = DoubleBuffer(args.bufferSizeBytes);

  // Receive buffer from main isolate
  // ... process with stepper ...
  // Send results back
}
```
