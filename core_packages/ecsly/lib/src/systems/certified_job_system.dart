import 'dart:async';
import 'dart:isolate';

import '../resources/resources.dart';
import '../world/world.dart';
import 'schedule_job_types.dart';

int currentScheduleExecutionFrame(final World world) {
  if (world.resources.has<ScheduleExecutionPolicyResource>()) {
    return world.getResource<ScheduleExecutionPolicyResource>().frameId;
  }
  return 0;
}

ScheduleExecutionPolicyResource resolveScheduleExecutionPolicy(
  final World world,
) {
  if (world.resources.has<ScheduleExecutionPolicyResource>()) {
    return world.getResource<ScheduleExecutionPolicyResource>();
  }
  return ScheduleExecutionPolicyResource();
}

ScheduleJobResultQueueResource resolveScheduleJobResultQueue(
  final World world,
) {
  if (world.resources.has<ScheduleJobResultQueueResource>()) {
    return world.getResource<ScheduleJobResultQueueResource>();
  }
  return ScheduleJobResultQueueResource();
}

abstract class CertifiedScheduleJobSystem {
  const CertifiedScheduleJobSystem();

  String get jobKey;

  void runSerial(final World world);

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

  Future<void> runBestEffort(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    await runDeterministic(world, policy: policy, queue: queue);
  }

  Future<void> runDeterministic(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    runSerial(world);
  }
}

abstract class PartitionedScheduleJobSystem<
  TExtract extends Object,
  TChunk extends Object,
  TResult extends Object
>
    extends CertifiedScheduleJobSystem {
  const PartitionedScheduleJobSystem();

  bool canRunInBackground(
    final World world,
    final ScheduleExecutionPolicyResource policy,
  ) => policy.workerCount > 1;

  TExtract extract(final World world);

  TResult executeChunk(final TChunk chunk);

  void merge(
    final World world,
    final List<ScheduleJobChunkResult<TResult>> orderedResults,
  );

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

    final futures = <Future<ScheduleJobChunkResult<TResult>>>[];
    for (final chunk in chunks) {
      futures.add(
        Isolate.run(
          () => ScheduleJobChunkResult<TResult>(
            chunkKey: chunk.chunkKey,
            value: executeChunk(chunk.payload),
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
              (final chunk) => Isolate.run(
                () => ScheduleJobChunkResult<TResult>(
                  chunkKey: chunk.chunkKey,
                  value: executeChunk(chunk.payload),
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
