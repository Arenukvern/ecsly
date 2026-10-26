import 'dart:async';

import 'package:async_parallel/async_parallel.dart';
import 'package:ecsly/ecsly.dart';

import 'resource.dart';
import 'schedule_job_types.dart';

/// Resolves the current schedule execution frame id from the world.
int currentScheduleExecutionFrame(final World world) {
  if (world.resources.has<ScheduleExecutionPolicyResource>()) {
    return world.getResource<ScheduleExecutionPolicyResource>().frameId;
  }
  return 0;
}

/// Resolves the active [ScheduleExecutionPolicyResource], defaulting when unset.
ScheduleExecutionPolicyResource resolveScheduleExecutionPolicy(
  final World world,
) {
  if (world.resources.has<ScheduleExecutionPolicyResource>()) {
    return world.getResource<ScheduleExecutionPolicyResource>();
  }
  return ScheduleExecutionPolicyResource();
}

/// Resolves the active [ScheduleJobResultQueueResource], defaulting when unset.
ScheduleJobResultQueueResource resolveScheduleJobResultQueue(
  final World world,
) {
  if (world.resources.has<ScheduleJobResultQueueResource>()) {
    return world.getResource<ScheduleJobResultQueueResource>();
  }
  return ScheduleJobResultQueueResource();
}

/// {@template schedule_parallel_task_system}
/// Base class for ECS-aware parallel task systems.
///
/// A job system partitions work into chunks, executes each chunk (possibly in
/// an isolate), and merges the ordered results back into the world. The
/// execution policy ([ScheduleExecutionPolicy]) controls *how* the chunks run:
///
/// * [ScheduleExecutionPolicy.serial] — run everything on the calling thread.
/// * [ScheduleExecutionPolicy.deterministic] — run chunks concurrently and merge
///   in the same frame, awaiting completion before returning.
/// * [ScheduleExecutionPolicy.bestEffort] — pipeline across frames: merge the
///   previous frame's results while spawning the current frame's work in the
///   background, so a slow frame never blocks the main loop.
/// {@endtemplate}
abstract class ScheduleParallelTaskSystem {
  /// {@macro schedule_parallel_task_system}
  const ScheduleParallelTaskSystem();

  /// Stable key used by the result queue to identify this job's envelopes.
  String get jobKey;

  /// Runs the job synchronously on the calling thread.
  void runSerial(final World world);

  /// The isolate backend used to execute chunks in background isolates.
  ///
  /// Override (or inject via constructor) to swap strategies — for example a
  /// pooled executor for hot paths, or a native backend when available.
  IsolateExecutor get isolateExecutor => const IsolateExecutorDart();

  /// Dispatches the job according to the world's execution policy.
  Future<void> runAsync(final World world) async {
    final policy = resolveScheduleExecutionPolicy(world);
    final queue = resolveScheduleJobResultQueue(world);
    switch (policy.mode) {
      case ScheduleExecutionPolicy.serial:
        runSerial(world);
      case ScheduleExecutionPolicy.deterministic:
        await runDeterministic(world, policy: policy, queue: queue);
      case ScheduleExecutionPolicy.bestEffort:
        await runBestEffort(world, policy: policy, queue: queue);
    }
  }

  /// Best-effort mode: merge the previous frame while spawning this frame.
  ///
  /// This is the only mode that pipelines. It never blocks on the current
  /// frame's background work — if a frame is already in flight it returns
  /// immediately so the main loop keeps running.
  ///
  /// Subclasses override to implement pipelined execution.
  Future<void> runBestEffort(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  });

  /// Deterministic mode: run all chunks concurrently and await completion.
  ///
  /// Falls back to [runSerial] when there is nothing to parallelize (fewer
  /// than two chunks, or no background workers configured).
  ///
  /// Subclasses override to implement concurrent chunk execution.
  Future<void> runDeterministic(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  });
}

/// {@template partitioned_schedule_job_system}
/// A job system whose work can be expressed as extract → partition →
/// execute-chunk → merge.
///
/// Subclasses implement the four hooks; the base class handles chunking,
/// ordering, and (for [ScheduleExecutionPolicy.deterministic] /
/// [ScheduleExecutionPolicy.bestEffort]) dispatching chunks to background
/// isolates via [isolateExecutor].
/// {@endtemplate}
abstract class PartitionedScheduleJobSystem<
  TExtract extends Object,
  TChunk extends Object,
  TResult extends Object
>
    extends ScheduleParallelTaskSystem {
  /// {@macro partitioned_schedule_job_system}
  const PartitionedScheduleJobSystem();

  /// Whether this job may run in a background isolate.
  ///
  /// Defaults to requiring more than one configured worker. Subclasses may
  /// refine this (e.g. gate on world state or buffer availability).
  bool canRunInBackground(
    final World world,
    final ScheduleExecutionPolicyResource policy,
  ) => policy.workerCount > 1;

  /// Extracts the per-frame work item from the world.
  TExtract extract(final World world);

  /// Runs a single chunk and returns its result.
  TResult executeChunk(final TChunk chunk);

  /// Merges ordered chunk results back into the world.
  void merge(
    final World world,
    final List<ScheduleJobChunkResult<TResult>> orderedResults,
  );

  /// Partitions the extracted work into chunks.
  List<ScheduleJobChunk<TChunk>> partition(
    final TExtract extracted,
    final ScheduleExecutionPolicyResource policy,
  );

  @override
  void runSerial(final World world) {
    final policy = resolveScheduleExecutionPolicy(world);
    final extracted = extract(world);
    final chunks = partition(extracted, policy);
    if (chunks.isEmpty) {
      merge(world, <ScheduleJobChunkResult<TResult>>[]);
      return;
    }

    final results = <ScheduleJobChunkResult<TResult>>[];
    for (final chunk in chunks) {
      results.add(
        ScheduleJobChunkResult<TResult>(
          chunkKey: chunk.chunkKey,
          value: executeChunk(chunk.payload),
        ),
      );
    }
    results.sort((final a, final b) => a.chunkKey.compareTo(b.chunkKey));
    merge(world, results);
  }

  @override
  Future<void> runDeterministic(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    if (!canRunInBackground(world, policy)) {
      runSerial(world);
      return;
    }

    final extracted = extract(world);
    final chunks = partition(extracted, policy);
    if (chunks.length <= 1) {
      runSerial(world);
      return;
    }

    // Each chunk runs in a background isolate via the pluggable executor.
    // Results are collected and merged in chunk-key order.
    final futures = <Future<ScheduleJobChunkResult<TResult>>>[];
    for (final chunk in chunks) {
      futures.add(
        isolateExecutor
            .compute<TChunk, TResult>(executeChunk, chunk.payload)
            .then(
              (final value) => ScheduleJobChunkResult<TResult>(
                chunkKey: chunk.chunkKey,
                value: value,
              ),
            ),
      );
    }

    final results = await Future.wait(futures);
    results.sort((final a, final b) => a.chunkKey.compareTo(b.chunkKey));
    merge(world, results);
  }

  @override
  Future<void> runBestEffort(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    final frameId = currentScheduleExecutionFrame(world);
    var mergedCompletedFrame = false;
    if (!canRunInBackground(world, policy)) {
      runSerial(world);
      return;
    }

    final completedFrameId = frameId - 1;
    if (completedFrameId >= 0) {
      queue.dropStaleResults(jobKey: jobKey, minFrameId: completedFrameId);
      final completed = queue.takeForFrame<TResult>(
        jobKey: jobKey,
        frameId: completedFrameId,
      );
      if (completed.isNotEmpty) {
        merge(world, completed);
        mergedCompletedFrame = true;
      }
    }

    if (queue.hasInFlightJob(jobKey)) {
      return;
    }

    final extracted = extract(world);
    final chunks = partition(extracted, policy);
    if (chunks.length <= 1) {
      if (!mergedCompletedFrame) {
        runSerial(world);
      }
      return;
    }

    if (!queue.beginInFlight(jobKey: jobKey, frameId: frameId)) {
      return;
    }

    unawaited(
      Future.wait(
            chunks.map(
              (final chunk) => isolateExecutor
                  .compute<TChunk, TResult>(executeChunk, chunk.payload)
                  .then(
                    (final value) => ScheduleJobChunkResult<TResult>(
                      chunkKey: chunk.chunkKey,
                      value: value,
                    ),
                  ),
            ),
          )
          .then((final results) {
            results.sort(
              (final a, final b) => a.chunkKey.compareTo(b.chunkKey),
            );
            queue.completeInFlight(
              ScheduleJobResultEnvelope<TResult>(
                jobKey: jobKey,
                frameId: frameId,
                results: results,
              ),
            );
          })
          .catchError((final _) {
            queue.cancelInFlight(jobKey: jobKey, frameId: frameId);
          }),
    );
  }
}
