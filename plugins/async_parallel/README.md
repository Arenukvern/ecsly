# async_parallel

**Zero-cost isolate management for high-performance Dart applications.**

TransferableTypedData double buffering, buffer pooling, isolate executor
seams, and malloc-backed shared memory abstractions for concurrent computing
without GC pressure. This is the ECS-agnostic primitive layer; the ECS job
systems built on it live in
[`ecsly_async_parallel`](../ecsly_async_parallel).

In the repo, in active development; not published (`publish_to: none`).
Depend on it through the pub workspace inside this repo, or via a git
dependency outside it. 51 tests cover the buffers, pools, and executor seams.

## Core Principles

- **Zero-Cost**: Minimal abstraction overhead, direct TypedData operations
- **Double Buffering**: Automatic ownership transfer between isolates
- **Shared Memory**: Optional malloc.allocate for zero-latency access
- **Typed-Data Friendly**: TypedData layout is preserved across isolate
  boundaries via `TransferableTypedData`, so views such as `Float32List` and
  `Int32List` remain valid on the receiving side

## Usage

### Double Buffering (Primary Strategy)

```dart
import 'package:async_parallel/async_parallel.dart';

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

### Isolate Executor & Pooling

`IsolateExecutor` is the pluggable seam for isolate execution:

```dart
// Fresh isolate per call (default)
final executor = IsolateExecutorDart();
await executor.compute(myFunction, message);

// Pooled isolates — amortizes startup cost for many small tasks
final pool = IsolateExecutorPoolDart(
  workerEntry: _myWorkerEntry,
  size: 4,
);
try {
  await pool.compute(myFunction, message);
} finally {
  await pool.shutdown();
}
```

`IsolateExecutorPool` keeps workers alive and dispatches work to idle
workers. The worker entry point must be a top-level or static function — the
work logic is fixed at pool construction. `IsolateExecutorPoolAdapter` wraps
the pool to satisfy the `IsolateExecutor` interface.

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

## Integration pattern

The primitives compose with any pure-algorithm workload that operates on
TypedData buffers — physics steppers, broad-phase scans, particle updates:

```dart
// Pure algorithms over TypedData are isolate-portable.
class SIMDPhysicsStepper {
  void step(Float32List positions, Float32List velocities, double dt) {
    // Pure SIMD physics computation
  }
}

// async_parallel handles concurrent execution.
void computeIsolate(_ComputeIsolateArgs args) {
  final stepper = SIMDPhysicsStepper();
  final buffer = DoubleBuffer(args.bufferSizeBytes);

  // Receive buffer from main isolate
  // ... process with stepper ...
  // Send results back
}
```
