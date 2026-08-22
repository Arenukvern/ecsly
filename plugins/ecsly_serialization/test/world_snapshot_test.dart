import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

class _NameCodec extends ObjectComponentCodec<NameComponent> {
  const _NameCodec();

  @override
  Object? toJson(final NameComponent component) => component.value;

  @override
  NameComponent fromJson(final Object? value) =>
      NameComponent(value as String? ?? '');
}

const _nameCodec = _NameCodec();

class GameConfig extends Resource with SnapshotableResource {
  GameConfig({this.speed = 100});

  final double speed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'speed': speed};

  // ignore: prefer_constructors_over_static_methods
  static GameConfig fromJson(final Map<String, Object?> json) =>
      GameConfig(speed: (json['speed'] as num?)?.toDouble() ?? 100);
}

void main() {
  test('full world round-trip: entities, columns, resources', () {
    final source = buildSerializationTestWorld();
    final a = source.spawnComponents([
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
    final b = source.spawnComponents([
      const PositionComponent(),
      const ScoreComponent(),
    ]);
    source.upsertResource(GameConfig(speed: 7));
    source.flush();

    final (extA, _) = source.getEntityExtension(a);
    extA.getOrCreate<PositionComponent, Position>()
      ..x = 10
      ..y = 20;
    extA.getOrCreate<HealthComponent, Health>().value = 55;
    extA.getOrCreate<ScoreComponent, Score>().value = 900;

    final (extB, _) = source.getEntityExtension(b);
    extB.getOrCreate<PositionComponent, Position>()
      ..x = -1
      ..y = -2;

    final snapshot = captureWorldSnapshot(source);
    expect(snapshot.version, worldSnapshotVersion);
    expect(snapshot.entities.length, 2);

    final target = buildSerializationTestWorld();
    // Recreate the same entity layout in the target world.
    final targetA = target.spawnComponents([
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
    final targetB = target.spawnComponents([
      const PositionComponent(),
      const ScoreComponent(),
    ]);
    target.flush();

    restoreWorldSnapshot(
      target,
      snapshot,
      resourceFactories: {'GameConfig': GameConfig.fromJson},
    );

    expect(target.resources.has<GameConfig>(), isTrue);
    expect((target.resources.getByType(GameConfig)! as GameConfig).speed, 7);

    final (restoredA, okA) = target.getEntityExtension(targetA);
    expect(okA, isTrue);
    expect(restoredA.getOrCreate<PositionComponent, Position>().x, 10);
    expect(restoredA.getOrCreate<PositionComponent, Position>().y, 20);
    expect(restoredA.getOrCreate<HealthComponent, Health>().value, 55);
    expect(restoredA.getOrCreate<ScoreComponent, Score>().value, 900);

    final (restoredB, okB) = target.getEntityExtension(targetB);
    expect(okB, isTrue);
    expect(restoredB.getOrCreate<PositionComponent, Position>().x, -1);
    expect(restoredB.getOrCreate<PositionComponent, Position>().y, -2);
  });

  test('JSON codec round-trip preserves snapshot', () {
    final source = buildSerializationTestWorld();
    source.spawnComponents([const PositionComponent()]);
    source.upsertResource(GameConfig(speed: 3.5));
    source.flush();

    final snapshot = captureWorldSnapshot(source);
    final encoded = encodeWorldSnapshot(snapshot);
    final decoded = decodeWorldSnapshot(encoded);

    expect(decoded.version, snapshot.version);
    expect(decoded.entities.length, snapshot.entities.length);
    expect(decoded.resources['GameConfig'], snapshot.resources['GameConfig']);
  });

  test('object components round-trip via codecs', () {
    final codecs = ObjectComponentCodecRegistry()..register(_nameCodec);
    final options = WorldSnapshotOptions(codecs: codecs);

    final source = buildSerializationTestWorld();
    final entity = source.spawnComponents([const NameComponent('hero')]);
    source.flush();

    final snapshot = captureWorldSnapshot(source, options: options);
    expect(snapshot.entities, isNotEmpty);

    final target = buildSerializationTestWorld();
    target.spawnComponents([const NameComponent('')]);
    target.flush();

    restoreWorldSnapshot(target, snapshot, options: options);

    final restored = target.getEntity(entity).$1.get<NameComponent>();
    expect(restored, isNotNull);
    expect(restored!.value, 'hero');
  });

  test('plugin installs config resource', () {
    final world = buildSerializationTestWorld();
    world.addPlugin(const SerializationPlugin());
    expect(world.hasPlugin('ecsly_serialization'), isTrue);
    expect(world.resources.has<SerializationConfigResource>(), isTrue);
  });
}
