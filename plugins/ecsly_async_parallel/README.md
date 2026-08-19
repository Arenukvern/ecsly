# ecsly_async_parallel

ECS-aware parallel task systems built on top of
[`async_parallel`](../async_parallel).

This package provides the ECS-specific job-system layer: a schedule extension
for registering job systems, an abstract partitioned task base class, and the
resources that back deterministic and best-effort execution.

The low-level primitives — `DoubleBuffer`, `TransferableBuffer`, `BufferPool`,
`SharedMemory`, `IsolateManager`, and the pluggable `IsolateExecutor` — live in
`async_parallel` and are ECS-agnostic. This package composes them into an ECS
context.

## Installation

```yaml
dependencies:
  ecsly_async_parallel:
  ecsly:
  async_parallel:
```

## Quick start

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
pooled or native implementation to change the execution model without touching
the job system:

```dart
class MyJobSystem extends PartitionedScheduleJobSystem<...> {
  @override
  IsolateExecutor get isolateExecutor => const MyPooledExecutor();
}
```

## Where the pieces live

| Concern | Package |
| --- | --- |
| Low-level primitives, `IsolateExecutor` seam | `async_parallel` |
| Job systems, schedule extension, result queue | `ecsly_async_parallel` |
| Schedules, `ScheduleExecutionPolicy`, executors | `ecsly` (core) |