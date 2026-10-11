import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:ecsly_world_sync_bridge/ecsly_world_sync_bridge.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'test_components.dart';

void main() {
  test('first emit captures every field; second emit is idempotent', () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    final ship = spawnShip(world, 1, health: true, score: true);
    writeColumn(world, ship, PositionComponent, 0, 1.5);
    writeColumn(world, ship, PositionComponent, 1, 2.5);
    writeColumn(world, ship, HealthComponent, 0, 55);
    writeColumn(world, ship, ScoreComponent, 0, 900);

    // Position(x,y) + Health + Score = exactly one op per captured field.
    expect(bridge.emitDeltas(), 4);
    expect(bridge.emitDeltas(), 0, reason: 'unchanged world emits nothing');

    final projection = sync.projection;
    expect(
      projection.componentValue(
        entityKey: '1',
        component: 'PositionComponent',
        field: '0',
      ),
      1.5,
    );
    expect(
      projection.componentValue(
        entityKey: '1',
        component: 'PositionComponent',
        field: '1',
      ),
      2.5,
    );
    expect(
      projection.componentValue(
        entityKey: '1',
        component: 'HealthComponent',
        field: '0',
      ),
      55,
    );
    expect(
      projection.componentValue(
        entityKey: '1',
        component: 'ScoreComponent',
        field: '0',
      ),
      900,
    );
    // Only the four captured fields exist — no extra keys, no runtime
    // entity handles anywhere in the key space.
    expect(projection.values.keys.toSet(), {
      '1/PositionComponent/0',
      '1/PositionComponent/1',
      '1/HealthComponent/0',
      '1/ScoreComponent/0',
    });
  });

  test('data-only change is caught even though structure did not change', () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    final ship = spawnShip(world, 1);
    expect(bridge.emitDeltas(), 2);

    final revisionBefore = world.structuralRevision;
    writeColumn(world, ship, PositionComponent, 0, 9.5);
    expect(world.structuralRevision, revisionBefore,
        reason: 'data writes do not bump the structural revision');

    // This is exactly why the bridge cannot gate diffs on the revision:
    // the only signal of this change is the capture diff itself.
    expect(bridge.emitDeltas(), 1);
    expect(
      sync.projection.componentValue(
        entityKey: '1',
        component: 'PositionComponent',
        field: '0',
      ),
      9.5,
    );
    expect(bridge.emitDeltas(), 0);
  });

  test('flush observer emits deltas on world.flush() without manual emit',
      () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    final previous = _RecordingObserver();
    world.flushObserver = previous;
    bridge.attach();
    expect(bridge.isAttached, isTrue);
    expect(identical(world.flushObserver, bridge.flushObserver), isTrue);

    final ship = spawnShip(world, 7, health: true);
    writeColumn(world, ship, HealthComponent, 0, 42);
    world.flush(); // no manual emitDeltas

    expect(
      sync.projection.componentValue(
        entityKey: '7',
        component: 'HealthComponent',
        field: '0',
      ),
      42,
    );
    expect(previous.started, greaterThan(0));
    expect(previous.ended, greaterThan(0),
        reason: 'the chained previous observer still sees flush callbacks');

    // Re-entrant flush (capture flushes internally) stays bounded: a second
    // flush of an unchanged world emits nothing and returns cleanly.
    world.flush();
    expect(
      sync.projection.componentValue(
        entityKey: '7',
        component: 'HealthComponent',
        field: '0',
      ),
      42,
    );

    // Detach restores the displaced observer.
    bridge.detach();
    expect(bridge.isAttached, isFalse);
    expect(identical(world.flushObserver, previous), isTrue);
  });

  test('despawn emits tombstones; replicas see the keys vanish', () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final remote = WorldSync(actorId: 'remote');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    final ship = spawnShip(world, 1, score: true);
    expect(bridge.emitDeltas(), 3);
    remote.applyRemote(sync.pendingOps);
    expect(remote.projection.values.length, 3);

    world.despawnEntity(ship);
    world.flush();
    expect(bridge.emitDeltas(), 3, reason: 'three tombstones');
    remote.applyRemote(sync.opsFor(remote.vv));

    expect(remote.projection.values, isEmpty);
    expect(sync.projection.values, isEmpty);
    expect(
      remote.projection.contains('1/PositionComponent/0'),
      isFalse,
      reason: 'tombstoned keys are absent',
    );
  });

  test('component removal tombstones only that component', () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    final ship = spawnShip(world, 1, score: true);
    expect(bridge.emitDeltas(), 3);

    world.removeComponent<ScoreComponent>(ship);
    world.flush();
    expect(bridge.emitDeltas(), 1);

    final projection = sync.projection;
    expect(projection.contains('1/ScoreComponent/0'), isFalse);
    expect(projection.contains('1/PositionComponent/0'), isTrue);
    expect(projection.contains('1/PositionComponent/1'), isTrue);
  });

  test('object components ride the obj field through a codec', () {
    final world = buildTestWorld();
    final codecs = ObjectComponentCodecRegistry()..register(const NameCodec());
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(
      world: world,
      sync: sync,
      codecs: codecs,
      clock: clock.tick,
    );

    final ship = spawnShip(
      world,
      1,
      position: false,
      name: const NameComponent('hero'),
    );
    expect(bridge.emitDeltas(), 1);
    expect(
      sync.projection.componentValue(
        entityKey: '1',
        component: 'NameComponent',
        field: 'obj',
      ),
      {'type': 'NameComponent', 'value': 'hero'},
    );

    // Name change is a data-only change on the object column.
    world.upsertComponent<NameComponent>(ship, const NameComponent('villain'));
    world.flush();
    expect(bridge.emitDeltas(), 1);
    expect(
      sync.projection.componentValue(
        entityKey: '1',
        component: 'NameComponent',
        field: 'obj',
      ),
      {'type': 'NameComponent', 'value': 'villain'},
    );
    expect(bridge.emitDeltas(), 0);
  });

  test('an entity without capturable columns is invisible to the bridge', () {
    final world = buildTestWorld();
    final clock = TestClock();
    final sync = WorldSync(actorId: 'a');
    final bridge = WorldSyncBridge(world: world, sync: sync, clock: clock.tick);

    // PersistentId is an object component; without a codec it has no
    // captured columns, so an entity carrying only it yields no keys.
    spawnShip(world, 1, position: false);
    expect(bridge.emitDeltas(), 0);
    expect(sync.projection.values, isEmpty);
  });

  test('two live worlds converge through session drivers', () async {
    // The dial discipline varies: A first, B first, or both at once. Which
    // side initiates must not matter — the script is symmetric and the
    // kernel's fold is order-insensitive.
    await _twoWorldScenario('a dials first', _DialDiscipline.aFirst);
    await _twoWorldScenario('b dials first', _DialDiscipline.bFirst);
    await _twoWorldScenario('both dial at once', _DialDiscipline.concurrent);
  });
}

/// How a round is kicked off between the two drivers.
enum _DialDiscipline { aFirst, bFirst, concurrent }

/// Full scenario: two live worlds, two bridges, two replicas; conflicting
/// concurrent writes; despawn; convergence under the given dial discipline;
/// redelivery idempotence.
Future<void> _twoWorldScenario(
  final String label,
  final _DialDiscipline discipline,
) async {
  final clock = TestClock();
  final worldA = buildTestWorld();
  final worldB = buildTestWorld();
  final syncA = WorldSync(actorId: 'world_a');
  final syncB = WorldSync(actorId: 'world_b');
  final bridgeA = WorldSyncBridge(
    world: worldA,
    sync: syncA,
    clock: clock.tick,
  );
  final bridgeB = WorldSyncBridge(
    world: worldB,
    sync: syncB,
    clock: clock.tick,
  );

  final pair = FakeMeshPair.paired(a: 'world_a', b: 'world_b');
  MeshPeerRecord recordOf(final String id) =>
      MeshPeerRecord(peerId: id, displayName: id);
  // Compaction triggers are off: this scenario proves convergence and
  // idempotence, not the (session-core-owned) compaction policy.
  final driverA = WorldSyncSession(
    sync: syncA,
    transport: pair.a,
    peerId: 'world_a',
    peers: {recordOf('world_b')},
    maxLogOps: null,
    minInterval: null,
  )..listen();
  final driverB = WorldSyncSession(
    sync: syncB,
    transport: pair.b,
    peerId: 'world_b',
    peers: {recordOf('world_a')},
    maxLogOps: null,
    minInterval: null,
  )..listen();

  // Independent spawns sharing a persistent id on both sides (this is what
  // makes the Position writes a true concurrent conflict).
  final shipA = spawnShip(worldA, 1, health: true, score: true);
  final ship1B = spawnShip(worldB, 1);
  final shipB = spawnShip(worldB, 2, score: true);

  // Writes interleaved on the shared clock: B's Position writes on pid 1
  // are issued after A's, so under LWW B wins those keys deterministically.
  writeColumn(worldA, shipA, PositionComponent, 0, 1.5);
  writeColumn(worldA, shipA, PositionComponent, 1, 2.5);
  writeColumn(worldA, shipA, HealthComponent, 0, 55);
  writeColumn(worldA, shipA, ScoreComponent, 0, 900);
  writeColumn(worldB, ship1B, PositionComponent, 0, 9.5);
  writeColumn(worldB, ship1B, PositionComponent, 1, 8.0);
  writeColumn(worldB, shipB, PositionComponent, 0, -1.0);
  writeColumn(worldB, shipB, PositionComponent, 1, -2.0);
  writeColumn(worldB, shipB, ScoreComponent, 0, 700);

  expect(bridgeA.emitDeltas(), 4, reason: label);
  expect(bridgeB.emitDeltas(), 5, reason: label);

  await _drive(driverA, driverB, discipline);

  final expected = <String, Object?>{
    '1/PositionComponent/0': 9.5, // B's later write wins LWW
    '1/PositionComponent/1': 8.0,
    '1/HealthComponent/0': 55, // only A has Health on pid 1
    '1/ScoreComponent/0': 900, // only A has Score on pid 1
    '2/PositionComponent/0': -1.0,
    '2/PositionComponent/1': -2.0,
    '2/ScoreComponent/0': 700,
  };
  expect(syncA.projection.values, expected, reason: label);
  expect(syncB.projection.values, expected, reason: label);
  expect(syncA.vv.toJson(), syncB.vv.toJson(), reason: label);

  // Despawn pid 2 on B, re-drive: keys tombstone out on both sides.
  worldB.despawnEntity(shipB);
  worldB.flush();
  expect(bridgeB.emitDeltas(), 3, reason: '$label (tombstones)');
  await _drive(driverA, driverB, discipline);

  final afterDespawn = <String, Object?>{
    '1/PositionComponent/0': 9.5,
    '1/PositionComponent/1': 8.0,
    '1/HealthComponent/0': 55,
    '1/ScoreComponent/0': 900,
  };
  expect(syncA.projection.values, afterDespawn, reason: label);
  expect(syncB.projection.values, afterDespawn, reason: label);
  expect(syncA.projection.contains('2/ScoreComponent/0'), isFalse);

  // Redelivery is idempotent: more rounds change nothing.
  final vvBefore = syncA.vv.toJson();
  await _drive(driverA, driverB, discipline);
  await _drive(driverA, driverB, discipline);
  expect(syncA.projection.values, afterDespawn, reason: label);
  expect(syncB.projection.values, afterDespawn, reason: label);
  expect(syncA.vv.toJson(), vvBefore, reason: label);
  expect(syncA.opsFor(syncB.vv), isEmpty);
  expect(syncB.opsFor(syncA.vv), isEmpty);
  expect(bridgeA.emitDeltas(), 0, reason: label);
  expect(bridgeB.emitDeltas(), 0, reason: label);

  driverA.stop();
  driverB.stop();
}

/// One anti-entropy round under [discipline], then the event loop settles
/// (responder halves finish in microtasks after sending their deltas).
Future<void> _drive(
  final WorldSyncSession driverA,
  final WorldSyncSession driverB,
  final _DialDiscipline discipline,
) async {
  switch (discipline) {
    case _DialDiscipline.aFirst:
      await driverA.tick();
      await driverB.tick();
    case _DialDiscipline.bFirst:
      await driverB.tick();
      await driverA.tick();
    case _DialDiscipline.concurrent:
      await Future.wait([driverA.tick(), driverB.tick()]);
  }
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _RecordingObserver implements WorldFlushObserver {
  int started = 0;
  int ended = 0;

  @override
  void onFlushEnd(
    final World world, {
    required final int elapsedMicroseconds,
    required final int commandsExecuted,
    required final int resourcesPushed,
    required final int resourcesRemoved,
  }) {
    ended++;
  }

  @override
  void onFlushStart(final World world) {
    started++;
  }
}
