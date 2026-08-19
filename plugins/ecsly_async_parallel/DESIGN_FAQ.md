# Design Decisions FAQ - ecsly_async_parallel

Quick reference for ecsly_async_parallel architectural choices and rationale.
Focus: **Why** the ECS job-system layer exists and how it relates to the core
and to `async_parallel`. See `async_parallel/DESIGN_FAQ.md` for the low-level
primitives.

## Package Purpose

**Q: Why does ecsly_async_parallel exist as a separate package?**
A: It owns the ECS-specific job-system layer: the `Schedule` extension
(`addJobSystem` / `thenJobSystem`), the `ScheduleParallelTaskSystem` /
`PartitionedScheduleJobSystem` base classes, and the result-queue resource.
The low-level primitives (`DoubleBuffer`, `TransferableBuffer`, `BufferPool`,
`SharedMemory`, `IsolateManager`, `IsolateExecutor`) live in `async_parallel`,
which is ECS-agnostic and publishable on its own. Splitting them lets algorithm
libraries consume the primitives without depending on `ecsly`, while ECS users
get the job-system wiring for free.

**Q: Why not put the job system in the core `ecsly` package?**
A: The core stays runtime-focused and pure Dart (entities, archetypes,
resources, events, commands, plugins, schedules). Job systems are an execution
strategy layered on top of schedules, and they depend on isolate primitives —
neither of which belong in the core. Keeping them in a plugin keeps the core
small and lets the async strategy evolve independently.

## Isolate Executor Seam

**Q: Why `IsolateExecutor` instead of calling `Isolate.run` directly?**
A: The abstraction decouples job systems from a specific isolate strategy.
`IsolateExecutorDart` (fresh isolate per call) is the default; a pooled or
native implementation can be substituted by overriding
`ScheduleParallelTaskSystem.isolateExecutor`. Callers never touch `Isolate.run`.
Trade-off: one indirection per chunk vs. hard-coded strategy.

**Q: Why is `IsolateExecutor` in `async_parallel` and not here?**
A: It references no ECS types — it is `Future<R> compute<Q, R>(fn, message)`.
It belongs in the generalized package so non-ECS consumers can use it, and so
the job layer can depend on it without creating a cycle (`async_parallel` does
not depend on `ecsly`; `ecsly_async_parallel` depends on both).

## Job System Abstractions

**Q: Why `ScheduleParallelTaskSystem` rather than a plain `System`?**
A: A plain system is `void Function(World)` or `Future<void> Function(World)`.
A job system additionally knows how to partition work, run chunks in background
isolates, and merge ordered results. The base class implements the three
execution policies (`serial`, `deterministic`, `bestEffort`) so subclasses only
implement `extract` / `partition` / `executeChunk` / `merge`.

**Q: Why `PartitionedScheduleJobSystem` as a further abstract layer?**
A: Most jobs share the same shape: extract → partition → execute chunk → merge.
The base class implements that loop and only calls the four hooks. Subclasses
stay small; the chunking, ordering, and isolate dispatch live in one place.

**Q: Why chunk-key ordering?**
A: Deterministic results require a stable merge order. Each chunk carries an
integer `chunkKey`; results are sorted by it before `merge` is called. This
makes `deterministic` mode reproducible across runs and platforms.

## Best-Effort Pipelining

**Q: Why pipeline across frames instead of awaiting within one frame?**
A: Awaiting blocks the main loop until every chunk completes. For heavy jobs
that means frame drops. Best-effort merges the *previous* frame's results
while spawning the current frame's work in the background and returns
immediately — so a slow frame never stalls the loop. Trade-off: one-frame
latency vs. bounded main-thread time.

**Q: How does best-effort stay correct?**
A: `ScheduleJobResultQueueResource` tracks in-flight work per `(jobKey,
frameId)`. Each frame drops results older than the previous frame, merges the
previous frame's completed results, and bails out if a job is already in
flight. Stale results (from a dropped frame) can never be merged, and a job
never runs twice for the same frame.

## Integration with the Core

**Q: How does a job system reach the schedule?**
A: `Schedule.addJobSystem` wraps the job's `runAsync` in a
`SystemDescriptor` and registers it like any other system, so it participates
in dependency ordering (`runAfter` / `runBefore`) and the executor's group
pipeline. `thenJobSystem` chains it after the last added system.

**Q: Why does the core not know about job systems?**
A: The consolidation that moved job-system logic here kept the core focused on
schedules and executors. The job system is a `System` (via `runAsync`) from the
core's perspective — the core never needs to know it partitions work. This keeps
the core's execution model simple and the plugin's policy logic isolated.

## Performance

**Q: Why not zero-copy transfer for chunk results today?**
A: Chunk payloads and results are arbitrary Dart objects (e.g. the collision
plugin's `_BroadPhaseChunkInput` holding `Int32List`/`Float32List` references).
They are copied across isolate boundaries by the VM. Zero-copy via
`TransferableBuffer` is available in `async_parallel` for callers whose data is
already a flat `TypedData` buffer — the job layer is the natural consumer once
extract/merge are refactored to work on raw buffers. Trade-off: generality vs.
zero-copy for hot paths.

**Q: When should I not use background isolates?**
A: When there are fewer than two chunks, when `workerCount <= 1`, or when the
per-chunk work is smaller than isolate startup cost. All three modes fall back
to `runSerial` automatically, so the caller does not need to special-case them.