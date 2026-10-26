# ecsly_async_parallel

ECS-aware parallel task systems built on top of
[`async_parallel`](../async_parallel).

This package provides the ECS-specific job-system layer: a schedule extension
for registering job systems, abstract base classes for partitioned and buffered
job systems, and the resources that back deterministic and best-effort execution.

The low-level primitives — `DoubleBuffer`, `TransferableBuffer`, `BufferPool`,
`SharedMemory`, `IsolateManager`, `IsolateExecutor`, and `IsolateExecutorPool` —
live in `async_parallel` and are ECS-agnostic. This package composes them into an ECS
context.

## Installation

```yaml
dependencies:
  ecsly_async_parallel:
  ecsly:
  async_parallel:
```

## Quick start

### Partitioned job system (copy-based)

Use `PartitionedScheduleJobSystem` when your chunk types are arbitrary Dart
objects. Chunks are copied across isolate boundaries by the VM.

```dart
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';

class MyJobSystem extends PartitionedScheduleJobSystem<List<int>, int, int> {
  @override
  String get jobKey => 'my.job';

  @override
  void runSerial(final World world) {
    // Fallback path used when there is nothing to parallelize.
  }

  @override
  List<int> extract(final World world) => const <int>[];

  @override
  int executeChunk(final int chunk) => chunk;

  @override
  void merge(
    final World world,
    final List<ScheduleJobChunkResult<int>> orderedResults,
  ) {}

  @override
  List<ScheduleJobChunk<int>> partition(
    final List<int> extracted,
    final ScheduleExecutionPolicyResource policy,
  ) => const <ScheduleJobChunk<int>>[];
}

// Register the job on a schedule.
final schedule = Schedule('Update')
  ..addJobSystem(MyJobSystem(), name: 'my.job.run');

// Control how it executes through the policy resource.
final policy = world.getResource<ScheduleExecutionPolicyResource>()
  ..mode = ScheduleExecutionPolicy.bestEffort
  ..workerCount = 4;
```

### Buffered job system (zero-copy)

Use `BufferedScheduleJobSystem` when your chunk data is already flat
`TypedData` (e.g. `Float32List`, `Int32List`). Chunks are transferred via
`TransferableTypedData` — zero-copy ownership transfer, no VM copy.

```dart
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';

/// Top-level worker entry — must be static or top-level for isolate execution.
void _doubleFloatsWorker(
  final SendPort replyTo,
  final TransferableTypedData chunk,
) {
  final received = TransferableBuffer(0)..receive(chunk);
  final input = received.data.buffer.asFloat32List();
  final output = Float32List(input.length);
  for (var i = 0; i < input.length; i++) {
    output[i] = input[i] * 2;
  }
  final transferable = TransferableTypedData.fromList([output]);
  replyTo.send([true, transferable]);
}

class DoubleFloatsJobSystem
    extends BufferedScheduleJobSystem<Float32List, Float32List> {
  DoubleFloatsJobSystem(this.input);

  final Float32List input;

  @override
  String get jobKey => 'my.double_floats';

  @override
  void Function(SendPort replyTo, TransferableTypedData chunk)
  get workerEntry => _doubleFloatsWorker;

  @override
  int get chunkStrideBytes => 16; // 4 floats per chunk

  @override
  Float32List extractTyped(final World world) => input;

  @override
  Float32List executeChunk(final Float32List chunk) {
    final output = Float32List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      output[i] = chunk[i] * 2;
    }
    return output;
  }

  @override
  void mergeTyped(
    final World world,
    final List<ScheduleJobChunkResult<Float32List>> orderedResults,
  ) {
    final total = orderedResults.fold<int>(
      0,
      (final sum, final r) => sum + r.value.length,
    );
    final merged = Float32List(total);
    var offset = 0;
    for (final r in orderedResults) {
      merged.setRange(offset, offset + r.value.length, r.value);
      offset += r.value.length;
    }
    world.resources.push(DoubledBuffer(merged));
  }
}

class DoubledBuffer extends Resource {
  DoubledBuffer(this.data);
  final Float32List data;
}
```

## Execution policies

`ScheduleExecutionPolicy` (owned by the `ecsly` core) selects the strategy:

| Mode | Behavior |
| --- | --- |
| `serial` | Run everything on the calling thread. |
| `deterministic` | Run chunks concurrently and await completion within the same frame. |
| `bestEffort` | Pipeline across frames: merge the previous frame's results while spawning the current frame's work in the background, so a slow frame never blocks the main loop. |

`bestEffort` is the only mode that pipelines. It tracks in-flight work through
`ScheduleJobResultQueueResource` and drops results older than the previous
frame, so stale results from a dropped frame can never be merged.

## Pluggable isolate backend

`ScheduleParallelTaskSystem.isolateExecutor` defaults to
`IsolateExecutorDart`, which spawns a fresh isolate per call. Swap it for a
pooled implementation to amortize isolate startup cost:

```dart
class MyJobSystem extends PartitionedScheduleJobSystem<...> {
  @override
  IsolateExecutor get isolateExecutor => IsolateExecutorPoolDart(
    workerEntry: _myWorkerEntry,
    size: 4,
  );
}
```

For `BufferedScheduleJobSystem`, override `dispatchChunk` to route through a
pooled executor instead of spawning a fresh isolate per chunk:

```dart
class MyBufferedJobSystem
    extends BufferedScheduleJobSystem<Float32List, Float32List> {
  final _pool = IsolateExecutorPoolDart(
    workerEntry: _myBufferedWorkerEntry,
    size: 4,
  );

  @override
  Future<List<Object?>> dispatchChunk(
    final TransferableTypedData payload,
    final void Function(SendPort replyTo, TransferableTypedData chunk) worker,
  ) {
    // Route through the pooled executor instead of Isolate.spawn.
    // The pool worker receives [SendPort replyTo, TransferableTypedData chunk]
    // and sends [true, TransferableTypedData result] back.
    return _pool.compute<List<Object?>, List<Object?>>(
      (_) => [],
      [ReceivePort().sendPort, payload],
    );
  }
}
```

## When to use which base class

| Scenario | Base class | Chunk type | Transfer |
| --- | --- | --- | --- |
| Arbitrary Dart objects | `PartitionedScheduleJobSystem` | Any `Object` | VM copy |
| Flat `TypedData` buffers | `BufferedScheduleJobSystem` | `TypedData` | Zero-copy (`TransferableTypedData`) |

Use `BufferedScheduleJobSystem` when your extract/merge can operate on raw
buffers — that is the point at which zero-copy actually pays off. The collision
plugin's broad-phase and narrow-phase chunks are the canonical example: they
already work with `Float32List` bounds and `Int32List` pair indices, so
packing them into flat buffers and transferring via `TransferableBuffer`
eliminates the per-chunk copy entirely.

## Where the pieces live

| Concern | Package |
| --- | --- |
| Low-level primitives, `IsolateExecutor` seam | `async_parallel` |
| Job systems, schedule extension, result queue | `ecsly_async_parallel` |
| Schedules, `ScheduleExecutionPolicy`, executors | `ecsly` (core) |
