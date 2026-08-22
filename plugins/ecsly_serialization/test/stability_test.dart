import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';
import 'serialization_test_components_alt.dart';

/// Stability evals: snapshots must survive structural changes to the target
/// world — registration reordering, added components, removed components,
/// and renames (via explicit migration).
///
/// Restore spawns fresh entities, so targets are always freshly built worlds.

World _populate(final World world) {
  registerPersistentId(world);
  for (var i = 0; i < 5; i++) {
    world.spawnComponents([
      PersistentId(i + 1),
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
  }
  world.flush();
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      final pid = persistentIdOf(world, entity)!.value;
      final (ext, ok) = world.getEntityExtension(entity);
      if (!ok) continue;
      ext.getOrCreate<PositionComponent, Position>()
        ..x = pid * 2.0
        ..y = pid * 3.0;
      ext.getOrCreate<HealthComponent, Health>().value = pid % 256;
      ext.getOrCreate<ScoreComponent, Score>().value = pid * 10;
    }
  }
  return world;
}

void main() {
  test('stability: snapshot survives component registration REORDER', () {
    // Source: standard order (Position, Health, Score).
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    // Target: same shapes, registered in REVERSE order.
    final reordered = buildReorderedWorld();

    // The alt world uses different type names, so remap by name first:
    // rewrite BOTH the component table and each entity's component list.
    final snapshot = decodeWorldSnapshot(encoded);
    String altName(final String name) => switch (name) {
      'PositionComponent' => 'AltPositionComponent',
      'HealthComponent' => 'AltHealthComponent',
      'ScoreComponent' => 'AltScoreComponent',
      _ => name,
    };
    final remappedIds = <String, int>{
      for (final entry in snapshot.componentIds.entries)
        altName(entry.key): entry.value,
    };
    final remappedEntities = [
      for (final entity in snapshot.entities)
        EntityEntry(
          persistentId: entity.persistentId,
          components: entity.components.map(altName).toList(),
          columns: entity.columns,
        ),
    ];
    final renamedSnapshot = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: remappedIds,
      resources: snapshot.resources,
      entities: remappedEntities,
    );

    restoreWorldSnapshot(reordered, renamedSnapshot);

    var verified = 0;
    for (final archetype in reordered.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(reordered, entity)!.value;
        final (ext, ok) = reordered.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<AltPositionComponent, AltPosition>().x,
          pid * 2.0,
          reason: 'pid $pid after reorder',
        );
        expect(ext.getOrCreate<AltScoreComponent, AltScore>().value, pid * 10);
        verified++;
      }
    }
    expect(verified, 5);
  });

  test('stability: snapshot survives ADDED component in target world', () {
    // Source entities carry only Position; the target world also registers
    // Health — restore still works because structure comes from the snapshot.
    final source = buildSerializationTestWorld();
    registerPersistentId(source);
    for (var i = 0; i < 3; i++) {
      source.spawnComponents([PersistentId(i + 1), const PositionComponent()]);
    }
    source.flush();
    for (final archetype in source.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(source, entity)!.value;
        final (ext, _) = source.getEntityExtension(entity);
        ext.getOrCreate<PositionComponent, Position>().x = pid * 2.0;
      }
    }
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    final extended = buildSerializationTestWorld();
    restoreWorldSnapshot(extended, decodeWorldSnapshot(encoded));

    var verified = 0;
    for (final archetype in extended.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(extended, entity)!.value;
        final (ext, ok) = extended.getEntityExtension(entity);
        if (!ok) continue;
        expect(ext.getOrCreate<PositionComponent, Position>().x, pid * 2.0);
        verified++;
      }
    }
    expect(verified, 3);
  });

  test('stability: snapshot survives REMOVED component in target world', () {
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    // Target only has Position registered.
    final reduced = buildPositionOnlyWorld();

    // Must not throw; Health/Score data is skipped.
    restoreWorldSnapshot(reduced, decodeWorldSnapshot(encoded));

    var verified = 0;
    for (final archetype in reduced.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(reduced, entity)!.value;
        final (ext, ok) = reduced.getEntityExtension(entity);
        if (!ok) continue;
        expect(ext.getOrCreate<PositionComponent, Position>().x, pid * 2.0);
        verified++;
      }
    }
    expect(verified, 5);
  });

  test('stability: strictComponents throws on missing component', () {
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    final reduced = buildPositionOnlyWorld();

    expect(
      () => restoreWorldSnapshot(
        reduced,
        decodeWorldSnapshot(encoded),
        options: const WorldSnapshotOptions(strictComponents: true),
      ),
      throwsStateError,
    );
  });

  test('stability: RenameComponentMigration fixes renamed components', () {
    final source = _populate(buildSerializationTestWorld());
    final raw = captureWorldSnapshot(source).toJson();

    // Simulate an old save where Position was called "Transform".
    final componentIds = raw['componentIds'] as Map<String, Object?>? ?? {};
    final positionId = componentIds.remove('PositionComponent');
    componentIds['Transform'] = positionId;

    final oldSave = jsonEncode(raw);

    // Migration chain: v1 → v2 renames Transform back to PositionComponent.
    final restored = decodeAndMigrateWorldSnapshot(oldSave, [
      const RenameComponentMigration(
        fromVersion: 1,
        oldName: 'Transform',
        newName: 'PositionComponent',
      ),
    ]);

    final target = buildSerializationTestWorld();
    restoreWorldSnapshot(target, restored);

    var verified = 0;
    for (final archetype in target.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(target, entity)!.value;
        final (ext, ok) = target.getEntityExtension(entity);
        if (!ok) continue;
        expect(ext.getOrCreate<PositionComponent, Position>().x, pid * 2.0);
        verified++;
      }
    }
    expect(verified, 5);
  });

  test('stability: missing migration step fails loudly', () {
    final raw = <String, Object?>{
      'version': 2,
      'schemaVersion': 5,
      'componentIds': <String, Object?>{},
      'resources': <String, Object?>{},
      'entities': <Object?>[],
    };

    expect(
      () => decodeAndMigrateWorldSnapshot(
        jsonEncode(raw),
        const [],
        targetVersion: 6,
      ),
      throwsStateError,
    );
  });

  test('stability: restore into a COMPLETELY EMPTY world resolves names', () {
    // The primary save/load flow: capture from a played world, restore into
    // a freshly-constructed world with zero live entities. Component name
    // resolution must come from the target's registry, not from any
    // previously-captured archetype.
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    final fresh = buildSerializationTestWorld(); // no entities spawned
    final mapping = restoreWorldSnapshot(fresh, decodeWorldSnapshot(encoded));
    expect(mapping.length, 5);

    // Strict mode must pass too:
    expect(
      () => restoreWorldSnapshot(
        buildSerializationTestWorld(),
        decodeWorldSnapshot(encoded),
        options: const WorldSnapshotOptions(strictComponents: true),
      ),
      returnsNormally,
    );
  });

  test('stability: schemaVersion round-trips through the envelope', () {
    final source = buildSerializationTestWorld();
    registerPersistentId(source);
    source.spawnComponents([const PersistentId(1), const PositionComponent()]);
    source.flush();

    final snapshot = captureWorldSnapshot(
      source,
      options: const WorldSnapshotOptions(schemaVersion: 7),
    );
    expect(snapshot.schemaVersion, 7);

    final decoded = decodeWorldSnapshot(encodeWorldSnapshot(snapshot));
    expect(decoded.schemaVersion, 7);
  });
}
