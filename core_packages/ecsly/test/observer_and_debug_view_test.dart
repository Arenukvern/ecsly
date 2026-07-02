import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  test('SystemExecutor does not require observer by default', () {
    final world = World();
    world.createSchedule('Update').add((_) {});
    expect(() => world.runSchedule('Update'), returnsNormally);
  });

  test('Execution observer receives callbacks', () {
    final observer = _RecordingObserver();
    final world = World(executionObserver: observer);

    world
        .createSchedule('Update')
        .add((_) {}, name: 'a')
        .then((_) {}, name: 'b');

    world.runSchedule('Update');

    expect(observer.scheduleStarts, 1);
    expect(observer.scheduleEnds, 1);
    expect(observer.systemStarts, 2);
    expect(observer.systemEnds, 2);
  });

  test('WorldDebugView snapshot contains schedules/archetypes/resources', () {
    final world = World();
    world.createSchedule('Update').add((_) {}, name: 'a');
    world.upsertResource(LevelStateResource(currentLevel: 'menu'));
    world.flushResourcesOnly();

    final snap = WorldDebugView(world).snapshot();
    expect(snap.schedules.any((final s) => s.name == 'Update'), isTrue);
    expect(snap.archetypeCount, isNonNegative);
    expect(
      snap.resources.any(
        (final r) =>
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
  void onScheduleEnd(final World world, final String scheduleName) {
    scheduleEnds += 1;
  }

  @override
  void onScheduleStart(
    final World world,
    final String scheduleName, {
    required final int systemCount,
  }) {
    scheduleStarts += 1;
  }

  @override
  void onSystemEnd(
    final World world,
    final String scheduleName,
    final SystemDescriptor system, {
    required final int elapsedMicroseconds,
    final Object? error,
    final StackTrace? stackTrace,
  }) {
    systemEnds += 1;
  }

  @override
  void onSystemStart(
    final World world,
    final String scheduleName,
    final SystemDescriptor system,
  ) {
    systemStarts += 1;
  }
}
