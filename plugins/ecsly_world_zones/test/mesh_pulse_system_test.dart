import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_world_zones/ecsly_world_zones.dart';
import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// The composability proof (ADR 0003 §1): the pulse runs through ecsly's
/// OWN schedule machinery — no new scheduler, no adapters between.
void main() {
  test('meshPulseSystem is an ordinary AsyncSystem driven by a schedule',
      () async {
    final world = World();
    var pulses = 0;
    final session = _CountingPulse(() => pulses++);

    final schedule = world.systems.getOrCreateSchedule(
      meshPulseScheduleId,
      trigger: const ManualTrigger(),
    );
    schedule.add(meshPulseSystem(session), name: 'mesh-pulse');

    await schedule.runAsync(world);
    expect(pulses, 1);

    await schedule.runAsync(world);
    expect(pulses, 2);
  });

  test('registerMeshPulseSchedule wires the default cadence in one call',
      () async {
    final world = World();
    var pulses = 0;
    final schedule = registerMeshPulseSchedule(
      world,
      _CountingPulse(() => pulses++),
      trigger: const ManualTrigger(),
    );

    await schedule.runAsync(world);
    expect(pulses, 1);
    expect(world.systems.hasSchedule(meshPulseScheduleId), isTrue);
  });

  test('the pulse composes alongside game systems in one schedule', () async {
    final world = World();
    final ran = <String>[];
    var pulses = 0;

    final schedule = world.systems.getOrCreateSchedule(
      const ScheduleId('tick'),
      trigger: const ManualTrigger(),
    );
    schedule.add((final world) => ran.add('ai'), name: 'ai');
    schedule.add(meshPulseSystem(_CountingPulse(() => pulses++)),
        name: 'mesh-pulse', runAfter: ['ai']);
    schedule.add((final world) => ran.add('render'), name: 'render',
        runAfter: ['mesh-pulse']);

    await schedule.runAsync(world);

    expect(ran, ['ai', 'render'], reason: 'game systems still ordered');
    expect(pulses, 1, reason: 'the pulse ran inside the dependency chain');
  });
}

final class _CountingPulse implements Pulseable {
  _CountingPulse(this._onPulse);

  final void Function() _onPulse;

  @override
  Future<void> pulse() async => _onPulse();
}
