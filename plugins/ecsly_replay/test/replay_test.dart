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

Entity? _entityWithPid(final World world, final int pid) {
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      if (persistentIdOf(world, entity)?.value == pid) return entity;
    }
  }
  return null;
}

Entity _spawnTransient(final World world) {
  final e = world.spawnComponents([const PositionComponent()]);
  world.flush();
  return e;
}

/// Log with checkpoints at ticks 0–2 and one event key at tick 1.
(ReplayLog log, CheckpointStore checkpoints) _sessionWithTicks() {
  final log = _emptyLog();
  final checkpoints = CheckpointStore(cadence: 1);
  final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

  final w0 = buildSerializationTestWorld();
  _heroAt(w0, 0);
  checkpoints.save(w0, 0);

  final w1 = buildSerializationTestWorld();
  _heroAt(w1, 1);
  recorder.recordCommand(tick: 1, outcome: _capture(w1), eventKey: 'evt-1');
  checkpoints.save(w1, 1);

  final w2 = buildSerializationTestWorld();
  _heroAt(w2, 2);
  recorder.recordCommand(tick: 2, outcome: _capture(w2));
  checkpoints.save(w2, 2);

  return (log, checkpoints);
}

World _inspectorWorld({final double heroX = 99, final bool withTransient = true}) {
  final world = buildSerializationTestWorld();
  _heroAt(world, heroX);
  if (withTransient) _spawnTransient(world);
  return world;
}

int _transientCount(final World world) {
  registerPersistentId(world);
  var count = 0;
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      if (persistentIdOf(world, entity) == null) count++;
    }
  }
  return count;
}

/// Checkpoints at ticks 0 and 2 only (cadence 2).
(ReplayLog log, CheckpointStore checkpoints, WorldSnapshot baseline)
    _sparseCheckpointSession() {
  final log = _emptyLog();
  final checkpoints = CheckpointStore(cadence: 2);
  final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

  final w0 = buildSerializationTestWorld();
  _heroAt(w0, 0);
  final baseline = _capture(w0);
  checkpoints.save(w0, 0);

  final w1 = buildSerializationTestWorld();
  _heroAt(w1, 1);
  recorder.recordCommand(tick: 1, outcome: _capture(w1));

  final w2 = buildSerializationTestWorld();
  _heroAt(w2, 2);
  recorder.recordCommand(tick: 2, outcome: _capture(w2));
  checkpoints.save(w2, 2);

  final w3 = buildSerializationTestWorld();
  _heroAt(w3, 3);
  recorder.recordCommand(tick: 3, outcome: _capture(w3));

  return (log, checkpoints, baseline);
}

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
      initialBaseline: _capture(w0),
    );
    final ok = player.verifyDeterminism(
      createColdWorld: buildSerializationTestWorld,
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

  test(
    'checkpoint reconcile and spawn agree on persistent captures (tick seeks)',
    () {
      final (log, checkpoints) = _sessionWithTicks();
      final reconcileWorld = _inspectorWorld();
      final spawnWorld = _inspectorWorld();

      final reconcilePlayer = ReplayPlayer(
        world: reconcileWorld,
        log: log,
        checkpoints: checkpoints,
      );
      final spawnPlayer = ReplayPlayer(
        world: spawnWorld,
        log: log,
        checkpoints: checkpoints,
        checkpointRestoreMode: CheckpointRestoreMode.spawn,
      );

      for (final tick in <int>[0, 2, 1, 2, 0]) {
        reconcilePlayer.seekToTick(tick);
        spawnPlayer.seekToTick(tick);
        expect(
          persistentCapturesEqual(
            capturePersistentKeyedColumns(reconcilePlayer.world),
            capturePersistentKeyedColumns(spawnPlayer.world),
          ),
          isTrue,
          reason: 'tick $tick',
        );
      }
    },
  );

  test(
    'checkpoint reconcile and spawn agree on persistent captures (eventKey)',
    () {
      final (log, checkpoints) = _sessionWithTicks();
      final reconcileWorld = _inspectorWorld();
      final spawnWorld = _inspectorWorld();

      final reconcilePlayer = ReplayPlayer(
        world: reconcileWorld,
        log: log,
        checkpoints: checkpoints,
      );
      final spawnPlayer = ReplayPlayer(
        world: spawnWorld,
        log: log,
        checkpoints: checkpoints,
        checkpointRestoreMode: CheckpointRestoreMode.spawn,
      );

      reconcilePlayer.seek(eventKey: 'evt-1');
      spawnPlayer.seek(eventKey: 'evt-1');
      expect(
        persistentCapturesEqual(
          capturePersistentKeyedColumns(reconcilePlayer.world),
          capturePersistentKeyedColumns(spawnPlayer.world),
        ),
        isTrue,
      );

      reconcilePlayer.seekToTick(0);
      spawnPlayer.seekToTick(0);
      expect(
        persistentCapturesEqual(
          capturePersistentKeyedColumns(reconcilePlayer.world),
          capturePersistentKeyedColumns(spawnPlayer.world),
        ),
        isTrue,
      );
    },
  );

  test('reconcile checkpoint keeps persisted Entity handle and transient row',
      () {
    final (log, checkpoints) = _sessionWithTicks();
    final world = _inspectorWorld(heroX: 50);
    final heroBefore = _entityWithPid(world, 1)!;
    final transientBefore = world.archetypes.all
        .expand((final a) => a.entities)
        .firstWhere((final e) => persistentIdOf(world, e) == null);

    final player = ReplayPlayer(world: world, log: log, checkpoints: checkpoints);
    player.seekToTick(2);
    player.seekToTick(1);

    final heroAfter = _entityWithPid(world, 1);
    expect(heroAfter, heroBefore);
    expect(world.entities.isAlive(heroBefore), isTrue);
    expect(world.entities.isAlive(transientBefore), isTrue);
    expect(_positionX(world), 1.0);
  });

  test('backward seek: transient kept vs despawned', () {
    final (log, checkpoints) = _sessionWithTicks();
    final keepWorld = _inspectorWorld(withTransient: false);
    final keepPlayer = ReplayPlayer(
      world: keepWorld,
      log: log,
      checkpoints: checkpoints,
    );
    keepPlayer.seekToTick(2);
    final transient = _spawnTransient(keepWorld);
    keepPlayer.seekToTick(0, transientPolicy: TransientPolicy.keep);
    expect(keepWorld.entities.isAlive(transient), isTrue);

    final despawnWorld = _inspectorWorld(withTransient: false);
    final despawnPlayer = ReplayPlayer(
      world: despawnWorld,
      log: log,
      checkpoints: checkpoints,
    );
    despawnPlayer.seekToTick(2);
    final transient2 = _spawnTransient(despawnWorld);
    despawnPlayer.seekToTick(0, transientPolicy: TransientPolicy.despawn);
    expect(despawnWorld.entities.isAlive(transient2), isFalse);
  });

  test('persisted Entity handle preserved with keep and despawn policies', () {
    final (log, checkpoints) = _sessionWithTicks();
    for (final policy in TransientPolicy.values) {
      final world = _inspectorWorld(withTransient: false);
      final heroBefore = _entityWithPid(world, 1)!;
      final player = ReplayPlayer(world: world, log: log, checkpoints: checkpoints);
      player.seekToTick(2, transientPolicy: policy);
      player.seekToTick(1, transientPolicy: policy);
      expect(_entityWithPid(world, 1), heroBefore);
    }
  });

  test('verifyDeterminism requires despawn and passes with it', () {
    final (log, checkpoints) = _sessionWithTicks();
    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    final player = ReplayPlayer(
      world: _inspectorWorld(withTransient: false),
      log: log,
      checkpoints: checkpoints,
      initialBaseline: _capture(w0),
    );
    expect(
      () => player.verifyDeterminism(
        createColdWorld: buildSerializationTestWorld,
        target: const ReplayPosition(tick: 2, seq: 0),
        initialSnapshot: _capture(w0),
        transientPolicy: TransientPolicy.keep,
      ),
      throwsArgumentError,
    );
    expect(
      player.verifyDeterminism(
        createColdWorld: buildSerializationTestWorld,
        target: const ReplayPosition(tick: 2, seq: 0),
        initialSnapshot: _capture(w0),
      ),
      isTrue,
    );
  });

  test('sparse checkpoints: seek 3 to 1 with transient keep vs despawn', () {
    final (log, checkpoints, baseline) = _sparseCheckpointSession();
    final keepWorld = _inspectorWorld(withTransient: false);
    final keepPlayer = ReplayPlayer(
      world: keepWorld,
      log: log,
      checkpoints: checkpoints,
      initialBaseline: baseline,
    );
    keepPlayer.seekToTick(3);
    _spawnTransient(keepWorld);
    keepPlayer.seekToTick(1, transientPolicy: TransientPolicy.keep);
    expect(_positionX(keepWorld), 1.0);
    expect(_transientCount(keepWorld), 1);

    final despawnWorld = _inspectorWorld(withTransient: false);
    final despawnPlayer = ReplayPlayer(
      world: despawnWorld,
      log: log,
      checkpoints: checkpoints,
      initialBaseline: baseline,
    );
    despawnPlayer.seekToTick(3);
    _spawnTransient(despawnWorld);
    despawnPlayer.seekToTick(1, transientPolicy: TransientPolicy.despawn);
    expect(_positionX(despawnWorld), 1.0);
    expect(_transientCount(despawnWorld), 0);
  });

  test('seek before first checkpoint uses initialBaseline', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 5);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    final baseline = _capture(w0);

    final w1 = buildSerializationTestWorld();
    _heroAt(w1, 1);
    recorder.recordCommand(tick: 1, outcome: _capture(w1));

    final w2 = buildSerializationTestWorld();
    _heroAt(w2, 2);
    checkpoints.save(w2, 2);

    final world = buildSerializationTestWorld();
    _heroAt(world, 99);
    _spawnTransient(world);
    final player = ReplayPlayer(
      world: world,
      log: log,
      checkpoints: checkpoints,
      initialBaseline: baseline,
    );
    player.seekToTick(1, transientPolicy: TransientPolicy.despawn);
    expect(_positionX(world), 1.0);
    expect(_transientCount(world), 0);
  });

  test(
    'reconcile and spawn captures agree when seeking with despawn policy',
    () {
      final (log, checkpoints) = _sessionWithTicks();
      final reconcileWorld = _inspectorWorld();
      final spawnWorld = _inspectorWorld();
      final reconcilePlayer = ReplayPlayer(
        world: reconcileWorld,
        log: log,
        checkpoints: checkpoints,
      );
      final spawnPlayer = ReplayPlayer(
        world: spawnWorld,
        log: log,
        checkpoints: checkpoints,
        checkpointRestoreMode: CheckpointRestoreMode.spawn,
      );
      for (final tick in <int>[0, 2, 1]) {
        reconcilePlayer.seekToTick(
          tick,
          transientPolicy: TransientPolicy.despawn,
        );
        spawnPlayer.seekToTick(
          tick,
          transientPolicy: TransientPolicy.despawn,
        );
        expect(
          persistentCapturesEqual(
            capturePersistentKeyedColumns(reconcilePlayer.world),
            capturePersistentKeyedColumns(spawnPlayer.world),
          ),
          isTrue,
        );
      }
    },
  );

  test('createColdWorld is isolated from hot world and template', () {
    final (log, checkpoints) = _sessionWithTicks();
    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    final template = buildSerializationTestWorld();
    _heroAt(template, 42);

    final hotWorld = buildSerializationTestWorld();
    _heroAt(hotWorld, 88);
    final player = ReplayPlayer(
      world: hotWorld,
      log: log,
      checkpoints: checkpoints,
      initialBaseline: _capture(w0),
    );

    World? coldRef;
    player.replayColdCapture(
      createColdWorld: () {
        coldRef = buildSerializationTestWorld();
        return coldRef!;
      },
      target: const ReplayPosition(tick: 2, seq: 0),
      initialSnapshot: _capture(w0),
    );
    expect(coldRef, isNotNull);
    _heroAt(coldRef!, 0);
    expect(_positionX(template), 42);
    expect(_positionX(hotWorld), 88);
  });

  test('persistedCapturesMatch detects divergence (verifyDeterminism gate)', () {
    final (log, checkpoints) = _sessionWithTicks();
    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    final player = ReplayPlayer(
      world: buildSerializationTestWorld(),
      log: log,
      checkpoints: checkpoints,
      initialBaseline: _capture(w0),
    );
    final cold = player.replayColdCapture(
      createColdWorld: buildSerializationTestWorld,
      target: const ReplayPosition(tick: 2, seq: 0),
      initialSnapshot: _capture(w0),
    );
    player.seekToTick(1, transientPolicy: TransientPolicy.despawn);
    expect(player.persistedCapturesMatch(cold), isFalse);
    expect(
      player.verifyDeterminism(
        createColdWorld: buildSerializationTestWorld,
        target: const ReplayPosition(tick: 2, seq: 0),
        initialSnapshot: _capture(w0),
      ),
      isTrue,
    );
  });

  test('verifyDeterminism with inputReplayer that reads transients', () {
    final log = _emptyLog();
    final checkpoints = CheckpointStore(cadence: 1);
    final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

    final w0 = buildSerializationTestWorld();
    _heroAt(w0, 0);
    checkpoints.save(w0, 0);

    final w1 = buildSerializationTestWorld();
    _heroAt(w1, 4);
    recorder.recordInput(tick: 1, inputType: 'step', data: const {});
    recorder.recordCommand(tick: 1, outcome: _capture(w1));

    var transientsSeenDuringInput = -1;
    final hotWorld = buildSerializationTestWorld();
    _heroAt(hotWorld, 99);
    _spawnTransient(hotWorld);

    final player = ReplayPlayer(
      world: hotWorld,
      log: log,
      checkpoints: checkpoints,
      initialBaseline: _capture(w0),
      inputReplayer: (final world, final type, final data) {
        transientsSeenDuringInput = _transientCount(world);
      },
    );

    expect(
      player.verifyDeterminism(
        createColdWorld: buildSerializationTestWorld,
        target: const ReplayPosition(tick: 1, seq: 1),
        initialSnapshot: _capture(w0),
      ),
      isTrue,
    );
    expect(transientsSeenDuringInput, 0);
    expect(_transientCount(hotWorld), 0);
  });
}
