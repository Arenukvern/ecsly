import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';
import 'serialization_test_components_alt.dart';

World _worldWithHero() {
  final world = buildSerializationTestWorld();
  registerPersistentEntity(world);
  final hero = world.spawnComponents([
    PersistentEntityComponent(PersistentEntity.sequence(1)),
    const PositionComponent(),
    const HealthComponent(),
  ]);
  final transient = world.spawnComponents([const PositionComponent()]);
  world.flush();
  final (ext, _) = world.getEntityExtension(hero);
  ext.getOrCreate<PositionComponent, Position>()
    ..x = 5
    ..y = 7;
  ext.getOrCreate<HealthComponent, Health>().value = 42;
  return world;
}

Map<String, Object?> _captureByPid(World world) {
  final snap = captureWorldSnapshot(world);
  return {
    for (final e in snap.entities) e.identity: e.columns,
  };
}

void main() {
  test('reconcile matches respawn oracle for full snapshot', () {
    final source = _worldWithHero();
    final snapshot = captureWorldSnapshot(source);

    final respawnWorld = buildSerializationTestWorld();
    restoreWorldSnapshot(respawnWorld, snapshot);

    final reconcileWorld = _worldWithHero();
    reconcileWorldSnapshot(reconcileWorld, snapshot);

    expect(_captureByPid(reconcileWorld), _captureByPid(respawnWorld));
  });

  test('reconcile despawns persisted entities absent from snapshot', () {
    final world = _worldWithHero();
    world.spawnComponents([
      PersistentEntityComponent(PersistentEntity.sequence(99)),
      const PositionComponent(),
    ]);
    world.flush();

    final snapshot = captureWorldSnapshot(world);
    final trimmed = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: snapshot.componentIds,
      resources: snapshot.resources,
      entities: snapshot.entities.where((e) => e.identity == '1').toList(),
    );

    reconcileWorldSnapshot(world, trimmed);
    expect(_entityWithIdentityPublic(world, '99'), isNull);
    expect(_entityWithIdentityPublic(world, '1'), isNotNull);
  });

  test('reconcile leaves non-persistent entities alone', () {
    final world = _worldWithHero();
    final beforeTransient = world.archetypes.all
        .expand((a) => a.entities)
        .where((e) => persistentEntityOf(world, e) == null)
        .length;

    final snapshot = captureWorldSnapshot(world);
    reconcileWorldSnapshot(world, snapshot);

    final afterTransient = world.archetypes.all
        .expand((a) => a.entities)
        .where((e) => persistentEntityOf(world, e) == null)
        .length;
    expect(afterTransient, beforeTransient);
  });

  test('reconcile adds and removes components on existing entity', () {
    final world = _worldWithHero();
    final snapshot = captureWorldSnapshot(world);

    final entity = _entityWithIdentityPublic(world, '1')!;
    world.removeComponent<HealthComponent>(entity);
    world.flush();
    expect(world.maybeGetComponent<HealthComponent>(entity), isNull);

    reconcileWorldSnapshot(world, snapshot);
    world.flush();
    final (ext, ok) = world.getEntityExtension(entity);
    expect(ok, isTrue);
    expect(ext.getOrCreate<HealthComponent, Health>().value, 42);
  });

  test('duplicate persistent identity in snapshot fails reconcile', () {
    final world = buildSerializationTestWorld();
    const bad = WorldSnapshot(
      version: worldSnapshotVersion,
      schemaVersion: 1,
      componentIds: {},
      resources: {},
      entities: [
        EntityEntry(
          identity: '1',
          components: ['PositionComponent'],
          columns: {},
        ),
        EntityEntry(
          identity: '1',
          components: ['PositionComponent'],
          columns: {},
        ),
      ],
    );
    expect(
      () => reconcileWorldSnapshot(world, bad),
      throwsA(isA<StateError>()),
    );
  });

  test('reconcile survives renamed/reordered component registration', () {
    final source = _worldWithHero();
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    final altWorld = buildReorderedWorld();
    final snapshot = decodeWorldSnapshot(encoded);
    String altName(String name) => switch (name) {
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
            identity: e.identity,
            components: e.components.map(altName).toList(),
            columns: e.columns,
          ),
      ],
    );

    final respawn = buildReorderedWorld();
    restoreWorldSnapshot(respawn, remapped);

    final reconcile = buildReorderedWorld();
    registerPersistentEntity(reconcile);
    reconcile.spawnComponents([
      PersistentEntityComponent(PersistentEntity.sequence(1)),
      const AltPositionComponent(),
    ]);
    reconcile.flush();
    reconcileWorldSnapshot(reconcile, remapped);

    expect(_captureByPid(reconcile).keys, _captureByPid(respawn).keys);
  });
}

Entity? _entityWithIdentityPublic(World world, String value) {
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      final pid = persistentEntityOf(world, entity);
      if (pid?.value == value) return entity;
    }
  }
  return null;
}
