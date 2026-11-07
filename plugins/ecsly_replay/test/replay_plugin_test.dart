import 'package:ecsly/ecsly.dart';
import 'package:ecsly_replay/ecsly_replay.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

ReplayPlugin _plugin() => ReplayPlugin(
  header: const ReplayLogHeader(
    formatVersion: replayLogFormatVersion,
    fingerprints: ReplayFingerprints(
      buildFingerprint: 'test-build',
      schemaFingerprint: 'schema-1',
    ),
  ),
  checkpointCadence: 1,
);

Entity _heroAt(final World world, final double x) {
  registerPersistentId(world);
  final e = world.spawnComponents([
    const PersistentId(1),
    const PositionComponent(),
    const HealthComponent(),
  ]);
  world.flush();
  _setX(world, e, x);
  return e;
}

void _setX(final World world, final Entity e, final double x) {
  final (ext, _) = world.getEntityExtension(e);
  ext.getOrCreate<PositionComponent, Position>().x = x;
}

double _positionX(final World world) {
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      if (persistentIdOf(world, entity)?.value == 1) {
        final (ext, ok) = world.getEntityExtension(entity);
        if (!ok) continue;
        return ext.getOrCreate<PositionComponent, Position>().x;
      }
    }
  }
  return double.nan;
}

void main() {
  test('install wires one coherent record-and-seek state', () {
    final world = buildSerializationTestWorld();
    world.addPlugin(_plugin());

    final state = world.getResource<ReplayStateResource>();
    expect(state.recorder.log, same(state.log));
    expect(state.recorder.checkpoints, same(state.checkpoints));
    expect(state.player.log, same(state.log));
    expect(state.player.checkpoints, same(state.checkpoints));
    expect(world.hasPlugin('ecsly_replay'), isTrue);
  });

  test('record and seek through the plugin-installed state', () {
    final world = buildSerializationTestWorld();
    world.addPlugin(_plugin());
    final state = world.getResource<ReplayStateResource>();

    final hero = _heroAt(world, 0);
    state.checkpoints.save(world, 0);

    _setX(world, hero, 1);
    state.recorder.recordCommand(tick: 1, outcome: captureWorldSnapshot(world));
    state.checkpoints.save(world, 1);

    _setX(world, hero, 2);
    state.recorder.recordCommand(tick: 2, outcome: captureWorldSnapshot(world));
    state.checkpoints.save(world, 2);

    state.player.seekToTick(1);
    expect(_positionX(world), 1.0);

    state.player.seekToTick(2);
    expect(_positionX(world), 2.0);

    state.player.seekToTick(0);
    expect(_positionX(world), 0.0);
  });

  test('duplicate install is rejected; uninstall removes the state', () {
    final world = buildSerializationTestWorld();
    world.addPlugin(_plugin());

    expect(
      () => world.addPlugin(_plugin()),
      throwsA(isA<PluginInstallationException>()),
    );

    expect(world.removePlugin('ecsly_replay'), isTrue);
    expect(world.maybeGetResource<ReplayStateResource>(), isNull);
  });
}
