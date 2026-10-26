import 'package:ecsly/ecsly.dart';
import 'package:ecsly_replay/ecsly_replay.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';
import 'serialization_test_components_alt.dart';

ReplayLog _emptyLog() => ReplayLog(
  header: ReplayLogHeader(
    formatVersion: replayLogFormatVersion,
    fingerprints: const ReplayFingerprints(
      buildFingerprint: 'test-build',
      schemaFingerprint: 'schema-1',
    ),
  ),
);

Entity _heroAt(final World world, final double x) {
  registerPersistentId(world);
  final e = world.spawnComponents([
    const PersistentId(1),
    const PositionComponent(),
    const HealthComponent(),
  ]);
  world.flush();
  final (ext, _) = world.getEntityExtension(e);
  ext.getOrCreate<PositionComponent, Position>().x = x;
  ext.getOrCreate<HealthComponent, Health>().value = 7;
  return e;
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

WorldSnapshot _capture(final World world) => captureWorldSnapshot(world);

void main() {
  test('seek forward and backward by tick', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 1);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    checkpoints.save(w0, 0);

    final w1 = buildSerializationTestWorld();
    _heroAt(w1, 1);
    recorder.recordCommand(tick: 1, outcome: _capture(w1), eventKey: 'e1');
    checkpoints.save(w1, 1);

    final w2 = buildSerializationTestWorld();
    _heroAt(w2, 2);
    recorder.recordCommand(tick: 2, outcome: _capture(w2));
    checkpoints.save(w2, 2);

    final playerWorld = buildSerializationTestWorld();
    _heroAt(playerWorld, 99);
    final player = ReplayPlayer(world: playerWorld, log: log, checkpoints: checkpoints);
    player.seekToTick(2);
    expect(_positionX(player.world), 2.0);

    player.seekToTick(1);
    expect(_positionX(player.world), 1.0);

    player.seekToTick(0);
    expect(_positionX(player.world), 0.0);
  });

  test('seek by opaque eventKey', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 10);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final base = buildSerializationTestWorld();
    _heroAt(base, 0);
    checkpoints.save(base, 0);

    final mid = buildSerializationTestWorld();
    _heroAt(mid, 5);
    recorder.recordCommand(
      tick: 1,
      outcome: _capture(mid),
      eventKey: 'harness:event:42',
    );

    final playerWorld = buildSerializationTestWorld();
    _heroAt(playerWorld, 99);
    final player = ReplayPlayer(world: playerWorld, log: log, checkpoints: checkpoints);
    player.seekToEventKey('harness:event:42');
    expect(_positionX(player.world), 5.0);
  });

  test('duplicate eventKey fails append', () {
    final log = _emptyLog();
    final recorder = ReplayRecorder(
      log: log,
      checkpoints: CheckpointStore(),
    );
    final a = buildSerializationTestWorld();
    _heroAt(a, 0);
    recorder.recordCommand(
      tick: 0,
      outcome: _capture(a),
      eventKey: 'dup',
    );
    final b = buildSerializationTestWorld();
    _heroAt(b, 1);
    expect(
      () => recorder.recordCommand(
        tick: 1,
        outcome: _capture(b),
        eventKey: 'dup',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('checkpoint invalidation after truncate', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 1);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    checkpoints.save(w0, 0);
    final w1 = buildSerializationTestWorld();
    _heroAt(w1, 1);
    recorder.recordCommand(tick: 1, outcome: _capture(w1));
    checkpoints.save(w1, 1);

    expect(checkpoints.snapshotAt(1), isNotNull);
    recorder.truncateFrom(const ReplayPosition(tick: 1, seq: 0));
    expect(checkpoints.snapshotAt(1), isNull);
    expect(checkpoints.snapshotAt(0), isNotNull);
  });

  test('cold replay matches hot seek (determinism)', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 1);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    checkpoints.save(w0, 0);
    final w3 = buildSerializationTestWorld();
    _heroAt(w3, 3);
    recorder.recordCommand(tick: 1, outcome: _capture(w3));
    checkpoints.save(w3, 1);
    final w9 = buildSerializationTestWorld();
    _heroAt(w9, 9);
    recorder.recordCommand(tick: 2, outcome: _capture(w9));

    final playerWorld = buildSerializationTestWorld();
    _heroAt(playerWorld, 99);
    final player = ReplayPlayer(
      world: playerWorld,
      log: log,
      checkpoints: checkpoints,
    );
    final ok = player.verifyDeterminism(
      emptyTemplate: buildSerializationTestWorld(),
      target: const ReplayPosition(tick: 2, seq: 0),
      initialSnapshot: _capture(w0),
    );
    expect(ok, isTrue);
  });

  test('replay codec round trip', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 5);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);
    final w = buildSerializationTestWorld();
    _heroAt(w, 4);
    checkpoints.save(w, 0);
    recorder.recordCommand(tick: 1, outcome: _capture(w), eventKey: 'k');

    final json = ReplaySessionCodec.encode(log: log, checkpoints: checkpoints);
    final (decodedLog, decodedCk) = ReplaySessionCodec.decode(json);
    expect(decodedLog.entries.length, 1);
    expect(decodedLog.positionForEventKey('k')?.tick, 1);
    expect(decodedCk.cadence, 5);
  });

  test('renamed component registration across worlds on replay', () {
    final source = buildSerializationTestWorld();
    _heroAt(source, 11);
    final encoded = encodeWorldSnapshot(_capture(source));

    final snapshot = decodeWorldSnapshot(encoded);
    String altName(final String name) => switch (name) {
      'PositionComponent' => 'AltPositionComponent',
      'HealthComponent' => 'AltHealthComponent',
      _ => name,
    };
    final remapped = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: {
        for (final e in snapshot.componentIds.entries)
          altName(e.key): e.value,
      },
      resources: snapshot.resources,
      entities: [
        for (final e in snapshot.entities)
          EntityEntry(
            persistentId: e.persistentId,
            components: e.components.map(altName).toList(),
            columns: e.columns,
          ),
      ],
    );

    final log = _emptyLog();
    final checkpoints = CheckpointStore();
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);
    final altWorld = buildReorderedWorld();
    registerPersistentId(altWorld);
    restoreWorldSnapshot(altWorld, remapped);
    altWorld.flush();
    checkpoints.save(altWorld, 0);
    recorder.recordCommand(tick: 1, outcome: remapped);

    final player = ReplayPlayer(
      world: buildReorderedWorld(),
      log: log,
      checkpoints: checkpoints,
    );
    player.seekToTick(1);
    Entity? hero;
    for (final archetype in player.world.archetypes.all) {
      for (final entity in archetype.entities) {
        if (persistentIdOf(player.world, entity)?.value == 1) {
          hero = entity;
          break;
        }
      }
    }
    expect(hero, isNotNull);
    final (ext, ok) = player.world.getEntityExtension(hero!);
    expect(ok, isTrue);
    expect(
      ext.getOrCreate<AltPositionComponent, AltPosition>().x,
      11.0,
    );
    expect(persistentIdOf(player.world, hero!)?.value, 1);
  });
}
