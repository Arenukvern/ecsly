import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

/// Dogfood: exercise the full save/load cycle the way a real game would —
/// build a world with mixed component tiers, snapshot to disk, rebuild,
/// restore, and verify gameplay-visible state.
class EnemyTag extends Component {
  const EnemyTag();
}

class GameMeta extends Resource with SnapshotableResource {
  GameMeta({this.level = 1, this.seed = 0});

  final int level;
  final int seed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'level': level,
    'seed': seed,
  };

  // ignore: prefer_constructors_over_static_methods
  static GameMeta fromJson(final Map<String, Object?> json) => GameMeta(
    level: (json['level'] as num?)?.toInt() ?? 1,
    seed: (json['seed'] as num?)?.toInt() ?? 0,
  );
}

World _buildGame() {
  final world = buildSerializationTestWorld();
  world.components.registerTagComponent<EnemyTag>();
  return world;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ecsly_dogfood');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('dogfood: save/load cycle across process-like boundary', () {
    // --- Session 1: play and save.
    final session1 = _buildGame();
    for (var i = 0; i < 50; i++) {
      session1.spawnComponents([
        const PositionComponent(),
        const HealthComponent(),
        const ScoreComponent(),
        if (i.isEven) const EnemyTag(),
      ]);
    }
    session1.upsertResource(GameMeta(level: 3, seed: 42));
    session1.flush();

    // Simulate some gameplay mutation on entities with index 1..9.
    final entities = session1.archetypes.all.expand((final a) => a.entities).toList();
    for (final entity in entities) {
      if (entity.indexValue < 1 || entity.indexValue > 9) continue;
      final (ext, ok) = session1.getEntityExtension(entity);
      if (!ok) continue;
      ext.getOrCreate<PositionComponent, Position>()
        ..x = entity.indexValue * 1.5
        ..y = entity.indexValue * -2.0;
      ext.getOrCreate<HealthComponent, Health>().value =
          entity.indexValue % 256;
      ext.getOrCreate<ScoreComponent, Score>().value = entity.indexValue * 100;
    }

    final saveFile = File('${tempDir.path}/save.json');
    saveFile.writeAsStringSync(
      encodeWorldSnapshot(captureWorldSnapshot(session1)),
    );

    // --- Session 2: fresh "process", load.
    final session2 = _buildGame();
    // Recreate identical structure: 50 entities in spawn order.
    for (var i = 0; i < 50; i++) {
      session2.spawnComponents([
        const PositionComponent(),
        const HealthComponent(),
        const ScoreComponent(),
        if (i.isEven) const EnemyTag(),
      ]);
    }
    session2.flush();

    final loaded = decodeWorldSnapshot(saveFile.readAsStringSync());
    restoreWorldSnapshot(
      session2,
      loaded,
      resourceFactories: {'GameMeta': GameMeta.fromJson},
    );

    // Verify gameplay-visible state survived.
    expect(session2.resources.getByType(GameMeta), isNotNull);
    expect((session2.resources.getByType(GameMeta)! as GameMeta).level, 3);
    expect((session2.resources.getByType(GameMeta)! as GameMeta).seed, 42);

    var verified = 0;
    for (final archetype in session2.archetypes.all) {
      for (final entity in archetype.entities) {
        final (ext, ok) = session2.getEntityExtension(entity);
        if (!ok) continue;
        final expectedIndex = entity.indexValue;
        if (expectedIndex >= 10 || expectedIndex == 0) continue;
        expect(
          ext.getOrCreate<PositionComponent, Position>().x,
          closeTo(expectedIndex * 1.5, 0.01),
          reason: 'entity index $expectedIndex',
        );
        expect(
          ext.getOrCreate<HealthComponent, Health>().value,
          expectedIndex % 256,
        );
        expect(
          ext.getOrCreate<ScoreComponent, Score>().value,
          expectedIndex * 100,
        );
        verified++;
      }
    }
    expect(verified, 9); // indices 1..9 were mutated
  });

  test('dogfood: snapshot determinism — same state produces same bytes', () {
    World build() {
      final world = _buildGame();
      for (var i = 0; i < 20; i++) {
        world.spawnComponents([
          const PositionComponent(),
          const ScoreComponent(),
        ]);
      }
      world.upsertResource(GameMeta(seed: 7));
      world.flush();
      return world;
    }

    final a = encodeWorldSnapshot(captureWorldSnapshot(build()));
    final b = encodeWorldSnapshot(captureWorldSnapshot(build()));
    expect(a, b, reason: 'identical worlds must serialize identically');
  });
}
