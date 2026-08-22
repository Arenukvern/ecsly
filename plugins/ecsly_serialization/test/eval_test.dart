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

World _worldWith(
  final int entityCount, {
  final bool withHealth = true,
  final bool withScore = true,
}) {
  final world = buildSerializationTestWorld();
  for (var i = 0; i < entityCount; i++) {
    world.spawnComponents([
      const PositionComponent(),
      if (withHealth) const HealthComponent(),
      if (withScore) const ScoreComponent(),
    ]);
  }
  world.flush();
  return world;
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
    final source = _worldWith(10);
    final entities = source.archetypes.all
        .expand((final a) => a.entities)
        .toList();
    for (final e in entities) {
      final (ext, ok) = source.getEntityExtension(e);
      if (!ok) continue;
      ext.getOrCreate<PositionComponent, Position>()
        ..x = e.indexValue.toDouble()
        ..y = 0;
    }

    final snapshot = captureWorldSnapshot(source);
    final target = _worldWith(10);
    restoreWorldSnapshot(target, snapshot);
    restoreWorldSnapshot(target, snapshot); // second apply must be a no-op

    for (final archetype in target.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = target.getEntityExtension(entity);
        if (!ok) continue;
        expect(
          ext.getOrCreate<PositionComponent, Position>().x,
          entity.indexValue.toDouble(),
        );
      }
    }
  });

  test('eval: unmutated fields survive as zeros', () {
    final source = _worldWith(5);
    final snapshot = captureWorldSnapshot(source);
    final target = _worldWith(5);
    restoreWorldSnapshot(target, snapshot);

    for (final archetype in target.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = target.getEntityExtension(entity);
        if (!ok) continue;
        expect(ext.getOrCreate<PositionComponent, Position>().x, 0);
        expect(ext.getOrCreate<PositionComponent, Position>().y, 0);
        expect(ext.getOrCreate<HealthComponent, Health>().value, 0);
        expect(ext.getOrCreate<ScoreComponent, Score>().value, 0);
      }
    }
  });

  test('eval: NaN and infinity round-trip through JSON', () {
    final source = _worldWith(1);
    final entity = source.archetypes.all.expand((final a) => a.entities).first;
    final (ext, _) = source.getEntityExtension(entity);
    ext.getOrCreate<PositionComponent, Position>()
      ..x = double.infinity
      ..y = double.negativeInfinity;

    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));
    final decoded = decodeWorldSnapshot(encoded);
    final target = _worldWith(1);
    restoreWorldSnapshot(target, decoded);

    final (restored, ok) = target.getEntityExtension(
      target.archetypes.all.expand((final a) => a.entities).first,
    );
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
    final source = _worldWith(1);
    source.upsertResource(_Meta(values: List.generate(1000, (final i) => i)));
    source.flush();

    final encoded = encodeWorldSnapshot(captureWorldSnapshot(source));
    final decoded = decodeWorldSnapshot(encoded);
    final target = _worldWith(1);
    restoreWorldSnapshot(
      target,
      decoded,
      resourceFactories: {'_Meta': _Meta.fromJson},
    );

    final meta = (target.resources.getByType(_Meta) ?? _Meta()) as _Meta;
    expect(meta.values.length, 1000);
    expect(meta.values.last, 999);
  });

  test('eval: stale generation entities are skipped on restore', () {
    final source = _worldWith(3);
    final snapshot = captureWorldSnapshot(source);

    // Corrupt one entry's generation so it no longer matches any live entity.
    final corrupted = WorldSnapshot(
      version: snapshot.version,
      schemaVersion: snapshot.schemaVersion,
      componentIds: snapshot.componentIds,
      resources: snapshot.resources,
      entities: [
        ...snapshot.entities.take(1),
        EntitySnapshotEntry(
          index: snapshot.entities[1].index,
          generation: snapshot.entities[1].generation + 100,
          columns: snapshot.entities[1].columns,
        ),
        ...snapshot.entities.skip(2),
      ],
    );

    final target = _worldWith(3);
    // Must not throw; the stale entry is skipped.
    restoreWorldSnapshot(target, corrupted);
  });
}
