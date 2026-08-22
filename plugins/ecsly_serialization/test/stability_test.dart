import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';
import 'serialization_test_components_alt.dart';

/// Stability evals: snapshots must survive structural changes to the target
/// world — registration reordering, added components, removed components,
/// and renames (via explicit migration).

World _populate(final World world) {
  for (var i = 0; i < 5; i++) {
    world.spawnComponents([
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
  }
  world.flush();
  final entities = world.archetypes.all
      .expand((final a) => a.entities)
      .toList();
  for (final e in entities) {
    final (ext, ok) = world.getEntityExtension(e);
    if (!ok) continue;
    ext.getOrCreate<PositionComponent, Position>()
      ..x = e.indexValue * 2.0
      ..y = e.indexValue * 3.0;
    ext.getOrCreate<HealthComponent, Health>().value = e.indexValue % 256;
    ext.getOrCreate<ScoreComponent, Score>().value = e.indexValue * 10;
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
    for (var i = 0; i < 5; i++) {
      reordered.spawnComponents([
        const AltPositionComponent(),
        const AltHealthComponent(),
        const AltScoreComponent(),
      ]);
    }
    reordered.flush();

    // The alt world uses different type names, so remap by name first:
    // rewrite the snapshot's component table to the alt names.
    final snapshot = decodeWorldSnapshot(encoded);
    final remappedIds = <String, int>{};
    for (final entry in snapshot.componentIds.entries) {
      final altName = switch (entry.key) {
        'PositionComponent' => 'AltPositionComponent',
        'HealthComponent' => 'AltHealthComponent',
        'ScoreComponent' => 'AltScoreComponent',
        _ => entry.key,
      };
      remappedIds[altName] = entry.value;
    }
    final renamedSnapshot = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: remappedIds,
      resources: snapshot.resources,
      entities: snapshot.entities,
    );

    restoreWorldSnapshot(reordered, renamedSnapshot);

    for (final archetype in reordered.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = reordered.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<AltPositionComponent, AltPosition>().x,
          entity.indexValue * 2.0,
          reason: 'index ${entity.indexValue} after reorder',
        );
        expect(
          ext.getOrCreate<AltScoreComponent, AltScore>().value,
          entity.indexValue * 10,
        );
      }
    }
  });

  test('stability: snapshot survives ADDED component in target world', () {
    final source = buildSerializationTestWorld();
    for (var i = 0; i < 3; i++) {
      source.spawnComponents([const PositionComponent()]);
    }
    source.flush();
    final encoded = encodeWorldSnapshot(
      captureWorldSnapshot(_populate(source)),
    );

    // Target adds Health on top of Position.
    final extended = buildSerializationTestWorld();
    for (var i = 0; i < 3; i++) {
      extended.spawnComponents([
        const PositionComponent(),
        const HealthComponent(),
      ]);
    }
    extended.flush();

    restoreWorldSnapshot(extended, decodeWorldSnapshot(encoded));

    for (final archetype in extended.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = extended.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<PositionComponent, Position>().x,
          entity.indexValue * 2.0,
        );
      }
    }
  });

  test('stability: snapshot survives REMOVED component in target world', () {
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    // Target only has Position.
    final reduced = buildPositionOnlyWorld();
    for (var i = 0; i < 5; i++) {
      reduced.spawnComponents([const PositionComponent()]);
    }
    reduced.flush();

    // Must not throw; Health/Score data is skipped.
    restoreWorldSnapshot(reduced, decodeWorldSnapshot(encoded));

    for (final archetype in reduced.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = reduced.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<PositionComponent, Position>().x,
          entity.indexValue * 2.0,
        );
      }
    }
  });

  test('stability: strictComponents throws on missing component', () {
    final source = _populate(buildSerializationTestWorld());
    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));

    final reduced = buildPositionOnlyWorld();
    for (var i = 0; i < 5; i++) {
      reduced.spawnComponents([const PositionComponent()]);
    }
    reduced.flush();

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

    final target = _populate(buildSerializationTestWorld());
    restoreWorldSnapshot(target, restored);

    for (final archetype in target.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = target.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<PositionComponent, Position>().x,
          entity.indexValue * 2.0,
        );
      }
    }
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
    final snapshot = decodeWorldSnapshot(encoded);
    restoreWorldSnapshot(fresh, snapshot);

    // Nothing to verify state-wise (no entities), but the remap must not
    // have thrown and strict mode must pass too:
    expect(
      () => restoreWorldSnapshot(
        buildSerializationTestWorld(),
        snapshot,
        options: const WorldSnapshotOptions(strictComponents: true),
      ),
      returnsNormally,
    );
  });

  test('stability: schemaVersion round-trips through the envelope', () {
    final source = buildSerializationTestWorld();
    source.spawnComponents([const PositionComponent()]);
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
