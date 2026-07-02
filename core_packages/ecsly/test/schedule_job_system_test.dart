import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

class _AliveFilteringQueueJobSystem extends CertifiedScheduleJobSystem {
  _AliveFilteringQueueJobSystem(this.mergedEntities);

  final List<_QueuedEntityRef> mergedEntities;

  @override
  String get jobKey => 'test.alive_filter';

  @override
  void runSerial(final World world) {}

  @override
  Future<void> runBestEffort(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    final mergeFrameId = policy.frameId - 1;
    if (mergeFrameId < 0) {
      return;
    }
    final results = queue.takeForFrame<_QueuedEntityRef>(
      jobKey: jobKey,
      frameId: mergeFrameId,
    );
    for (final result in results) {
      if (world.entities.isAlive(result.value.toEntity())) {
        mergedEntities.add(result.value);
      }
    }
  }
}

class _QueuedEntityRef {
  const _QueuedEntityRef({required this.index, required this.generation});

  final int generation;
  final int index;

  Entity toEntity() => Entity.create(index, generation);
}

class _QueueBackedPartitionedJobSystem
    extends PartitionedScheduleJobSystem<List<int>, int, int> {
  _QueueBackedPartitionedJobSystem(this.mergedValues);

  final List<int> mergedValues;

  @override
  String get jobKey => 'test.partitioned.queue_backed';

  @override
  List<int> extract(final World world) => const <int>[];

  @override
  int executeChunk(final int chunk) => chunk;

  @override
  void merge(
    final World world,
    final List<ScheduleJobChunkResult<int>> orderedResults,
  ) {
    mergedValues.addAll(orderedResults.map((final result) => result.value));
  }

  @override
  List<ScheduleJobChunk<int>> partition(
    final List<int> extracted,
    final ScheduleExecutionPolicyResource policy,
  ) => const <ScheduleJobChunk<int>>[];
}

void main() {
  group('Schedule Job System', () {
    test(
      'deterministic policy keeps uncertified systems serial on async schedule execution',
      () async {
        final world = World();
        final policy = world.getResource<ScheduleExecutionPolicyResource>()
          ..mode = ScheduleExecutionPolicy.deterministic
          ..workerCount = 4;
        policy.markFrame(1);

        final calls = <String>[];
        final schedule = Schedule('AsyncOrder')
          ..add((final _) => calls.add('a'), name: 'a')
          ..then((final _) => calls.add('b'), name: 'b')
          ..then((final _) => calls.add('c'), name: 'c');

        await schedule.runAsync(world);

        expect(calls, ['a', 'b', 'c']);
      },
    );

    test(
      'result queue takes matching frame results and drops stale entries',
      () {
        final world = World();
        final queue = world.getResource<ScheduleJobResultQueueResource>();

        queue.completeInFlight(
          const ScheduleJobResultEnvelope<int>(
            jobKey: 'queue.test',
            frameId: 2,
            results: [ScheduleJobChunkResult<int>(chunkKey: 0, value: 11)],
          ),
        );
        queue.completeInFlight(
          const ScheduleJobResultEnvelope<int>(
            jobKey: 'queue.test',
            frameId: 5,
            results: [ScheduleJobChunkResult<int>(chunkKey: 0, value: 22)],
          ),
        );

        expect(
          queue.takeForFrame<int>(jobKey: 'queue.test', frameId: 4),
          isEmpty,
        );
        expect(queue.dropStaleResults(jobKey: 'queue.test', minFrameId: 5), 1);

        final matches = queue.takeForFrame<int>(
          jobKey: 'queue.test',
          frameId: 5,
        );
        expect(matches.map((final result) => result.value).toList(), [22]);
      },
    );

    test('best-effort queue merge ignores stale entity generations', () async {
      final world = World();
      final policy = world.getResource<ScheduleExecutionPolicyResource>()
        ..mode = ScheduleExecutionPolicy.bestEffort
        ..workerCount = 2
        ..markFrame(7);
      final queue = world.getResource<ScheduleJobResultQueueResource>();

      final entity = world.entities.create();
      queue.completeInFlight(
        ScheduleJobResultEnvelope<_QueuedEntityRef>(
          jobKey: 'test.alive_filter',
          frameId: 6,
          results: [
            ScheduleJobChunkResult<_QueuedEntityRef>(
              chunkKey: 0,
              value: _QueuedEntityRef(
                index: entity.indexValue,
                generation: entity.generation.value,
              ),
            ),
          ],
        ),
      );

      final (worldEntity, isValid) = world.getEntity(entity);
      expect(isValid, isTrue);
      worldEntity.despawn();
      world.flush();

      final merged = <_QueuedEntityRef>[];
      final jobSystem = _AliveFilteringQueueJobSystem(merged);
      await jobSystem.runBestEffort(world, policy: policy, queue: queue);

      expect(merged, isEmpty);
    });

    test(
      'partitioned best-effort merges previous-frame results in chunk order',
      () async {
        final world = World();
        final policy = world.getResource<ScheduleExecutionPolicyResource>()
          ..mode = ScheduleExecutionPolicy.bestEffort
          ..workerCount = 4
          ..markFrame(9);
        final queue = world.getResource<ScheduleJobResultQueueResource>();
        queue.completeInFlight(
          const ScheduleJobResultEnvelope<int>(
            jobKey: 'test.partitioned.queue_backed',
            frameId: 8,
            results: [
              ScheduleJobChunkResult<int>(chunkKey: 2, value: 30),
              ScheduleJobChunkResult<int>(chunkKey: 0, value: 10),
              ScheduleJobChunkResult<int>(chunkKey: 1, value: 20),
            ],
          ),
        );

        final merged = <int>[];
        final jobSystem = _QueueBackedPartitionedJobSystem(merged);
        await jobSystem.runBestEffort(world, policy: policy, queue: queue);

        expect(merged, [10, 20, 30]);
      },
    );

    test(
      'partitioned best-effort drops results older than previous frame',
      () async {
        final world = World();
        final policy = world.getResource<ScheduleExecutionPolicyResource>()
          ..mode = ScheduleExecutionPolicy.bestEffort
          ..workerCount = 4
          ..markFrame(9);
        final queue = world.getResource<ScheduleJobResultQueueResource>();
        queue.completeInFlight(
          const ScheduleJobResultEnvelope<int>(
            jobKey: 'test.partitioned.queue_backed',
            frameId: 7,
            results: [ScheduleJobChunkResult<int>(chunkKey: 0, value: 10)],
          ),
        );

        final merged = <int>[];
        final jobSystem = _QueueBackedPartitionedJobSystem(merged);
        await jobSystem.runBestEffort(world, policy: policy, queue: queue);

        expect(merged, isEmpty);
        expect(
          queue.takeForFrame<int>(
            jobKey: 'test.partitioned.queue_backed',
            frameId: 7,
          ),
          isEmpty,
        );
      },
    );
  });
}
