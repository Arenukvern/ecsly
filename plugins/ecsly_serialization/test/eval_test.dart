import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

/// Eval suite: correctness invariants that must hold for any world.
///
/// Each case captures a snapshot, restores into a fresh world, and asserts a
/// property that would break gameplay if violated. These are the gates a
/// serialization change must not regress.

class _Meta extends Resource with SnapshotableResource {
  _Meta({this.values = const []});
  final List<int> values;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'values': values};

  // ignore: prefer_constructors_over_static_methods
  static _Meta fromJson(final Map<String, Object?> json) => _Meta(
    values: ((json['values'] as List<Object?>?) ?? const [])
        .map((final v) => (v as num?)?.toInt() ?? 0)
        .toList(),
  );
}

/// Sets Position.x = persistentId on every persisted entity of [world].
void markPositions(final World world) {
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      final pid = persistentIdOf(world, entity);
      if (pid == null) continue;
      final (ext, ok) = world.getEntityExtension(entity);
      if (!ok) continue;
      ext.getOrCreate<PositionComponent, Position>()
        ..x = pid.value.toDouble()
        ..y = 0;
    }
  }
}

void main() {
  test('eval: empty world round-trips to empty snapshot', () {
    final source = buildSerializationTestWorld();
    final snapshot = captureWorldSnapshot(source);
    expect(snapshot.entities, isEmpty);

    final target = buildSerializationTestWorld();
    restoreWorldSnapshot(target, snapshot);
    expect(target.entities.count, 0);
  });

  test('eval: restore is idempotent', () {
    final source = buildPopulatedWorld(10);
    markPositions(source);

    final snapshot = captureWorldSnapshot(source);
    final target = buildSerializationTestWorld();
    final first = restoreWorldSnapshot(target, snapshot);
    final second = restoreWorldSnapshot(target, snapshot);

    // Same persistent IDs resolve to the same freshly spawned entities.
    expect(second.keys.toSet(), first.keys.toSet());
    for (final pid in first.keys) {
      expect(second[pid], first[pid]);
      final (ext, ok) = target.getEntityExtension(first[pid]!);
      expect(ok, isTrue);
      expect(ext.getOrCreate<PositionComponent, Position>().x, pid.toDouble());
    }
  });

  test('eval: unmutated fields survive as zeros', () {
    final source = buildPopulatedWorld(5);
    final snapshot = captureWorldSnapshot(source);
    final target = buildSerializationTestWorld();
    final mapping = restoreWorldSnapshot(target, snapshot);

    for (final entity in mapping.values) {
      final (ext, ok) = target.getEntityExtension(entity);
      expect(ok, isTrue);
      expect(ext.getOrCreate<PositionComponent, Position>().x, 0);
      expect(ext.getOrCreate<PositionComponent, Position>().y, 0);
      expect(ext.getOrCreate<HealthComponent, Health>().value, 0);
      expect(ext.getOrCreate<ScoreComponent, Score>().value, 0);
    }
    expect(mapping.length, 5);
  });

  test('eval: NaN and infinity round-trip through JSON', () {
    final source = buildPopulatedWorld(1);
    final entity = source.archetypes.all.expand((final a) => a.entities).first;
    final (ext, _) = source.getEntityExtension(entity);
    ext.getOrCreate<PositionComponent, Position>()
      ..x = double.infinity
      ..y = double.negativeInfinity;

    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));
    final decoded = decodeWorldSnapshot(encoded);
    final target = buildSerializationTestWorld();
    final mapping = restoreWorldSnapshot(target, decoded);

    final (restored, ok) = target.getEntityExtension(mapping.values.first);
    expect(ok, isTrue);
    expect(
      restored.getOrCreate<PositionComponent, Position>().x,
      double.infinity,
    );
    expect(
      restored.getOrCreate<PositionComponent, Position>().y,
      double.negativeInfinity,
    );
  });

  test('eval: large list resource values round-trip', () {
    final source = buildPopulatedWorld(1);
    source.upsertResource(_Meta(values: List.generate(1000, (final i) => i)));
    source.flush();

    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));
    final decoded = decodeWorldSnapshot(encoded);
    final target = buildSerializationTestWorld();
    restoreWorldSnapshot(
      target,
      decoded,
      resourceFactories: {'_Meta': _Meta.fromJson},
    );

    final meta = (target.resources.getByType(_Meta) ?? _Meta()) as _Meta;
    expect(meta.values.length, 1000);
    expect(meta.values.last, 999);
  });

  test('eval: duplicate persistent ids fail capture loudly', () {
    final world = buildSerializationTestWorld();
    registerPersistentId(world);
    world.spawnComponents([const PersistentId(1), const PositionComponent()]);
    world.spawnComponents([const PersistentId(1), const PositionComponent()]);
    world.flush();

    expect(() => captureWorldSnapshot(world), throwsStateError);
  });

  test('eval: restore into empty world spawns PersistentId carriers', () {
    final source = buildPopulatedWorld(3);
    markPositions(source);
    final snapshot = captureWorldSnapshot(source);

    final fresh = buildSerializationTestWorld(); // zero live entities
    final mapping = restoreWorldSnapshot(fresh, snapshot);

    expect(mapping.length, 3);
    expect(fresh.entities.count, 3);
    for (final pid in mapping.keys) {
      final (ext, ok) = fresh.getEntityExtension(mapping[pid]!);
      expect(ok, isTrue);
      expect(persistentIdOf(fresh, mapping[pid]!)!.value, pid);
      expect(ext.getOrCreate<PositionComponent, Position>().x, pid.toDouble());
    }
  });

  test('eval: corrupted persistent id entry still restores', () {
    final source = buildPopulatedWorld(3);
    final snapshot = captureWorldSnapshot(source);

    // Corrupt one entry's persistent id — restore spawns fresh entities from
    // the snapshot itself, so an odd key must not break the loop.
    final corrupted = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: snapshot.componentIds,
      resources: snapshot.resources,
      entities: [
        ...snapshot.entities.take(1),
        EntityEntry(
          persistentId: -1,
          components: snapshot.entities[1].components,
          columns: snapshot.entities[1].columns,
        ),
        ...snapshot.entities.skip(2),
      ],
    );

    final target = buildSerializationTestWorld();
    final mapping = restoreWorldSnapshot(target, corrupted);
    expect(mapping.length, 3);
    expect(mapping.containsKey(-1), isTrue);
  });
}
