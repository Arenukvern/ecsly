import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  test('SystemExecutor does not require observer by default', () {
    final world = World();
    world.createSchedule(ScheduleId.update).add((_) {});
    expect(() => world.runSchedule(ScheduleId.update), returnsNormally);
  });

  test('Execution observer receives callbacks', () {
    final observer = _RecordingObserver();
    final world = World(executionObserver: observer);

    world
        .createSchedule(ScheduleId.update)
        .add((_) {}, name: 'a')
        .then((_) {}, name: 'b');

    world.runSchedule(ScheduleId.update);

    expect(observer.scheduleStarts, 1);
    expect(observer.scheduleEnds, 1);
    expect(observer.systemStarts, 2);
    expect(observer.systemEnds, 2);
  });

  test('WorldDebugView snapshot contains schedules/archetypes/resources', () {
    final world = World();
    world.createSchedule(ScheduleId.update).add((_) {}, name: 'a');
    world.upsertResource(LevelStateResource(currentLevel: 'menu'));
    world.flushResourcesOnly();

    final snap = WorldDebugView(world).snapshot();
    expect(
      snap.schedules.any((s) => s.name == ScheduleId.update.value),
      isTrue,
    );
    expect(snap.archetypeCount, isNonNegative);
    expect(
      snap.resources.any(
        (r) =>
            r.type == LevelStateResource && (r.exists || r.isPendingPush),
      ),
      isTrue,
    );
  });
}

class _RecordingObserver extends EcsExecutionObserverBase {
  int scheduleStarts = 0;
  int scheduleEnds = 0;
  int systemStarts = 0;
  int systemEnds = 0;

  @override
  void onScheduleEnd(World world, String scheduleName) {
    scheduleEnds += 1;
  }

  @override
  void onScheduleStart(
    World world,
    String scheduleName, {
    required int systemCount,
  }) {
    scheduleStarts += 1;
  }

  @override
  void onSystemEnd(
    World world,
    String scheduleName,
    SystemDescriptor system, {
    required int elapsedMicroseconds,
    Object? error,
    StackTrace? stackTrace,
  }) {
    systemEnds += 1;
  }

  @override
  void onSystemStart(
    World world,
    String scheduleName,
    SystemDescriptor system,
  ) {
    systemStarts += 1;
  }
}
