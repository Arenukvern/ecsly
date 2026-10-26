import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

void main() {
  test('captures and restores SoA columns for an entity', () {
    final world = buildSerializationTestWorld();
    final entity = world.spawnComponents([
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
    world.flush();

    final (ext, ok) = world.getEntityExtension(entity);
    expect(ok, isTrue);
    ext.getOrCreate<PositionComponent, Position>()
      ..x = 1.5
      ..y = -2.5;
    ext.getOrCreate<HealthComponent, Health>().value = 200;
    ext.getOrCreate<ScoreComponent, Score>().value = 1234;

    final snapshot = captureEntityColumns(world, entity);
    expect(snapshot, isNotNull);

    // Mutate, then restore.
    ext.getOrCreate<PositionComponent, Position>()
      ..x = 0
      ..y = 0;
    restoreEntityColumns(world, entity, snapshot!);

    final (ext2, ok2) = world.getEntityExtension(entity);
    expect(ok2, isTrue);
    expect(ext2.getOrCreate<PositionComponent, Position>().x, 1.5);
    expect(ext2.getOrCreate<PositionComponent, Position>().y, -2.5);
    expect(ext2.getOrCreate<HealthComponent, Health>().value, 200);
    expect(ext2.getOrCreate<ScoreComponent, Score>().value, 1234);
  });

  test('includeOnly limits captured components', () {
    final world = buildSerializationTestWorld();
    final entity = world.spawnComponents([
      const PositionComponent(),
      const ScoreComponent(),
    ]);
    world.flush();

    final scoreId = world.components.getComponentId<ScoreComponent>();
    final snapshot = captureEntityColumns(
      world,
      entity,
      includeOnly: {scoreId},
    );

    expect(snapshot!.length, 1);
  });

  test('returns null for invalid entities', () {
    final world = buildSerializationTestWorld();
    // ignore: avoid_redundant_argument_values
    final ghost = Entity.create(9999, 0);
    final result = captureEntityColumns(world, ghost);
    expect(result, isNull);
  });
}
