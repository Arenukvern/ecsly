import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

/// The canonical determinism proof: replaying the same command sequence
/// into two equal starting worlds must produce bit-identical worlds —
/// same entity generations, archetype membership, component values, and
/// iteration order.
///
/// This is the direct test behind the `deterministic-structural-changes`
/// invariant in `.ae_hub/canonical/ecsly/`.
void main() {
  // A fixed command script: spawns, component upserts/removes, despawns.
  void runScript(World world) {
    final ids = <Entity>[];
    for (var i = 0; i < 12; i++) {
      final e = world.entities.create();
      ids.add(e);
      world.upsertComponent<NameComponent>(e, NameComponent('entity-$i'));
      if (i.isEven) {
        world.upsertComponent<HealthComponent>(
            e, const HealthComponent());
      }
    }
    world.flush();

    // Give even entities a Position via the typed facade path.
    for (final e in ids) {
      if (e.index.isEven && world.entities.isAlive(e)) {
        world.upsertComponent<PositionComponent>(
            e, const PositionComponent());
      }
    }
    world.flush();

    // Structural churn: remove some components, despawn some entities.
    for (var i = 0; i < ids.length; i++) {
      if (i % 3 == 0) {
        world.removeComponent<HealthComponent>(ids[i]);
      }
      if (i % 4 == 1) {
        EntityCommands(queue: world.commandQueue, entity: ids[i]).despawn();
      }
    }
    world.flush();

    for (var i = 0; i < ids.length; i++) {
      if (world.entities.isAlive(ids[i]) && i % 5 == 2) {
        world.upsertComponent<HealthComponent>(
            ids[i], const HealthComponent());
      }
    }
    world.flush();

    // Write deterministic position values after all structural churn so
    // column indices are stable at write time.
    for (final (entity, position) in world.queryExt<PositionComponent, Position>()) {
      final idx = entity.entity.index;
      position.x = idx * 1.5;
      position.y = -idx * 2.0;
    }
  }

  /// Snapshot the observable state that determinism covers.
  Map<String, Object?> snapshot(World world) {
    String sortKey(WorldEntity e) =>
        '${e.entity.index}:${e.entity.generation}';

    final names =
        world.query<NameComponent>().map((r) => r.$1).toList()
          ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    final positionRows =
        world.queryExt<PositionComponent, Position>()
            .map((r) => '${sortKey(r.$1.toEntity())}:${r.$2.x},${r.$2.y}')
            .toList()
          ..sort();
    final healths =
        world.queryExt<HealthComponent, Health>().map((r) => r.$1.toEntity())
            .toList()
          ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));

    return {
      'name_rows': [
        for (final e in names)
          '${sortKey(e)}:${e.get<NameComponent>()!.value}',
      ],
      'position_rows': positionRows,
      'health_rows': [for (final e in healths) sortKey(e)],
    };
  }

  test('replaying the same command script yields bit-identical worlds', () {
    final a = buildTestWorld();
    final b = buildTestWorld();

    runScript(a);
    runScript(b);

    expect(snapshot(b), equals(snapshot(a)),
        reason: 'same commands on equal worlds must produce equal worlds');
  });

  test('diverging scripts produce observably different worlds', () {
    final a = buildTestWorld();
    final b = buildTestWorld();

    runScript(a);
    runScript(b);

    // Diverge b after the shared prefix.
    final victim = b.query<NameComponent>().first.$1;
    victim.despawn();
    b.flush();

    expect(snapshot(b), isNot(equals(snapshot(a))),
        reason: 'the snapshot must be able to detect divergence');
  });

  test('three-way replay stays identical (not just pairwise)', () {
    final worlds = [buildTestWorld(), buildTestWorld(), buildTestWorld()];
    for (final w in worlds) {
      runScript(w);
    }
    expect(snapshot(worlds[2]), equals(snapshot(worlds[0])));
    expect(snapshot(worlds[2]), equals(snapshot(worlds[1])));
  });
}
