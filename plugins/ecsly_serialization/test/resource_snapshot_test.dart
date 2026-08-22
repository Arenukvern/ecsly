import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

class GameConfig extends Resource with SnapshotableResource {
  GameConfig({this.speed = 100, this.name = 'default'});

  final double speed;
  final String name;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'speed': speed,
    'name': name,
  };

  // ignore: prefer_constructors_over_static_methods
  static GameConfig fromJson(final Map<String, Object?> json) => GameConfig(
    speed: (json['speed'] as num? ?? 100).toDouble(),
    name: json['name'] as String? ?? 'default',
  );
}

class HiddenResource extends Resource {}

World _world() => buildSerializationTestWorld();

void main() {
  test('captures and restores snapshotable resources', () {
    final world = _world();
    world.upsertResource(GameConfig(speed: 42, name: 'fast'));
    world.upsertResource(HiddenResource());
    world.flush();

    final snapshot = captureResourceSnapshot(world);
    expect(snapshot.containsKey('GameConfig'), isTrue);
    expect(snapshot.containsKey('HiddenResource'), isFalse);

    final target = _world();
    restoreResourceSnapshot(target, snapshot, {
      'GameConfig': GameConfig.fromJson,
    });

    expect(target.resources.has<GameConfig>(), isTrue);
    final config = target.resources.getByType(GameConfig)! as GameConfig;
    expect(config.speed, 42);
    expect(config.name, 'fast');
  });

  test('restore ignores unknown resource types', () {
    final target = _world();
    restoreResourceSnapshot(target, const <String, Object?>{
      'Missing': <String, Object?>{'x': 1},
    }, const <String, SnapshotResourceFactory>{});
    expect(target.resources.iterDense().length, greaterThanOrEqualTo(0));
    // No throw is the contract.
  });
}
