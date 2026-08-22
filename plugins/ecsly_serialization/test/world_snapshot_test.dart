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
    registerPersistentId(source);
    final a = source.spawnComponents([
      const PersistentId(1),
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
    final b = source.spawnComponents([
      const PersistentId(2),
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

    // Restore into a completely fresh world — no pre-spawned structure.
    final target = buildSerializationTestWorld();
    restoreWorldSnapshot(
      target,
      snapshot,
      resourceFactories: {'GameConfig': GameConfig.fromJson},
    );

    expect(target.resources.has<GameConfig>(), isTrue);
    expect((target.resources.getByType(GameConfig)! as GameConfig).speed, 7);

    // Resolve restored entities via their PersistentIds.
    var verified = 0;
    for (final archetype in target.archetypes.all) {
      for (final entity in archetype.entities) {
        final pid = persistentIdOf(target, entity)!.value;
        final (ext, ok) = target.getEntityExtension(entity);
        expect(ok, isTrue);
        if (pid == 1) {
          expect(ext.getOrCreate<PositionComponent, Position>().x, 10);
          expect(ext.getOrCreate<PositionComponent, Position>().y, 20);
          expect(ext.getOrCreate<HealthComponent, Health>().value, 55);
          expect(ext.getOrCreate<ScoreComponent, Score>().value, 900);
          verified++;
        } else if (pid == 2) {
          expect(ext.getOrCreate<PositionComponent, Position>().x, -1);
          expect(ext.getOrCreate<PositionComponent, Position>().y, -2);
          verified++;
        }
      }
    }
    expect(verified, 2);
  });

  test('JSON codec round-trip preserves snapshot', () {
    final source = buildSerializationTestWorld();
    registerPersistentId(source);
    source.spawnComponents([const PersistentId(1), const PositionComponent()]);
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
    registerPersistentId(source);
    source.spawnComponents([
      const PersistentId(1),
      const NameComponent('hero'),
    ]);
    source.flush();

    final snapshot = captureWorldSnapshot(source, options: options);
    expect(snapshot.entities, isNotEmpty);

    final target = buildSerializationTestWorld();
    final mapping = restoreWorldSnapshot(target, snapshot, options: options);

    final restored = target
        .getEntity(mapping.values.first)
        .$1
        .get<NameComponent>();
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
