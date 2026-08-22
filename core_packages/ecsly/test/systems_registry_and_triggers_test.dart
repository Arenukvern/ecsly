import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('SystemsRegistry', () {
    test('create/get/getOrCreate/remove/tryGet/clear and names cache', () {
      final systems = SystemsRegistry();

      final s1 = systems.createSchedule(const ScheduleId('A'));
      expect(systems.hasSchedule(const ScheduleId('A')), isTrue);
      expect(systems.getSchedule(const ScheduleId('A')), same(s1));
      expect(systems.getOrCreateSchedule(const ScheduleId('A')), same(s1));
      expect(systems.scheduleNames, contains('A'));

      expect(
        () => systems.createSchedule(const ScheduleId('A')),
        throwsA(isA<EcsStateError>()),
      );
      expect(
        () => systems.getSchedule(const ScheduleId('missing')),
        throwsA(isA<EcsStateError>()),
      );

      final s2 = systems.getOrCreateSchedule(
        const ScheduleId('B'),
        trigger: const EveryFrame(),
      );
      expect(systems.tryGetSchedule(const ScheduleId('B')), same(s2));
      expect(systems.removeSchedule(const ScheduleId('B')), isTrue);
      expect(systems.removeSchedule(const ScheduleId('B')), isFalse);
      expect(systems.tryGetSchedule(const ScheduleId('B')), isNull);

      systems.clear();
      expect(systems.scheduleNames, isEmpty);
    });
  });

  group('ScheduleTrigger variants', () {
    test('ConditionTrigger/EveryFrame/ManualTrigger', () {
      final world = World();
      expect(ConditionTrigger((final _) => true).shouldRun(world), isTrue);
      expect(ConditionTrigger((final _) => false).shouldRun(world), isFalse);
      expect(const EveryFrame().shouldRun(world), isTrue);
      expect(const ManualTrigger().shouldRun(world), isTrue);
    });

    test('EveryNFrames fires at configured cadence', () {
      final world = World();
      final trigger = EveryNFrames(2);

      expect(trigger.shouldRun(world), isFalse);
      expect(trigger.shouldRun(world), isTrue);
      expect(trigger.shouldRun(world), isFalse);
      expect(trigger.shouldRun(world), isTrue);
    });

    test('EveryNSeconds uses DeltaTimeResource accumulation', () {
      final world = World();
      world.upsertResource(ScheduleTimeResource(deltaSeconds: 0.4));
      final trigger = EveryNSeconds(1);

      expect(trigger.shouldRun(world), isFalse);
      expect(trigger.shouldRun(world), isFalse);
      expect(trigger.shouldRun(world), isTrue);
    });

    test('ThrottledTrigger requires elapsed time between runs', () {
      final world = World();
      world.upsertResource(ScheduleTimeResource(deltaSeconds: 0));
      final trigger = ThrottledTrigger(
        const EveryFrame(),
        minIntervalSeconds: 0.5,
      );

      // First call at t=0 is throttled because no interval has elapsed yet.
      expect(trigger.shouldRun(world), isFalse);
      world.getResource<ScheduleTimeResource>().elapsedSeconds = 0.5;
      expect(trigger.shouldRun(world), isTrue);
      expect(trigger.shouldRun(world), isFalse);
      world.getResource<ScheduleTimeResource>().elapsedSeconds = 1.0;
      expect(trigger.shouldRun(world), isTrue);
    });
  });
}
