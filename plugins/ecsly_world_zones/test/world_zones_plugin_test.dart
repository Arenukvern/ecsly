import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_world_zones/ecsly_world_zones.dart';
import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  test('plugin registers the pulse schedule; uninstall removes it', () async {
    final world = World();
    var pulses = 0;
    world.addPlugin(
      WorldZonesPlugin(
        _CountingPulse(() => pulses++),
        trigger: const ManualTrigger(),
      ),
    );

    expect(world.hasPlugin('ecsly_world_zones'), isTrue);
    expect(world.systems.hasSchedule(meshPulseScheduleId), isTrue);

    await world.systems.getSchedule(meshPulseScheduleId).runAsync(world);
    expect(pulses, 1);

    expect(world.removePlugin('ecsly_world_zones'), isTrue);
    expect(world.systems.hasSchedule(meshPulseScheduleId), isFalse);
  });

  test('duplicate install is rejected', () {
    final world = World();
    world.addPlugin(WorldZonesPlugin(_CountingPulse(() {})));
    expect(
      () => world.addPlugin(WorldZonesPlugin(_CountingPulse(() {}))),
      throwsA(isA<PluginInstallationException>()),
    );
  });
}

final class _CountingPulse implements Pulseable {
  _CountingPulse(this._onPulse);

  final void Function() _onPulse;

  @override
  Future<void> pulse() async => _onPulse();
}
