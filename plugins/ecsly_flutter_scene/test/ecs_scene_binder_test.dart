// ignore_for_file: prefer_final_parameters, prefer_const_constructors
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recording_sink.dart';

/// The diffing law: a static world costs nothing per frame; a spawn
/// ADDs, a change UPDATEs (signature-diffed), a despawn REMOVEs.
void main() {
  test('mapping collects one visual per carrying entity, keyed stably', () {
    final world = buildWorld();
    final mapping = SceneMapping()
      ..add<Marker>(
        (entity, marker, world) => VisualState(
          shape: SceneShape.sphere,
          argb: 0xFF00AAFF,
          size: 1,
          position: [0, 0, 0],
          label: marker.kind,
        ),
      );
    final a = world.spawnComponents([const Marker('actor')]);
    world.spawnComponents([const Marker('step')]);
    world.flush();

    final collected = mapping.collect(world);
    expect(collected, hasLength(2));
    expect(
      collected.keys.map((k) => k.split('|').first),
      everyElement('Marker'),
    );
    expect(collected['Marker|e${a.toJson()}']?.label, 'actor');
  });

  test(
    'binder diff: spawn adds, change updates, despawn removes',
    () {
    final world = buildWorld();
    final mapping = SceneMapping()
      ..add<Marker>(
        (entity, marker, world) => VisualState(
          shape: SceneShape.cuboid,
          argb: marker.kind == 'hot' ? 0xFFFF4444 : 0xFF888888,
          size: 1,
          position: [0, 0, 0],
        ),
      );
    final sink = RecordingSink();
    final binder = EcsSceneBinder(
      world: world,
      sink: sink,
      mapping: mapping,
    );

    final entity = world.spawnComponents([const Marker('cold')]);
    world.flush();

    binder.sync();
    expect(sink.adds, hasLength(1));
    expect(sink.updates, isEmpty);

    // Static frame: NOTHING moves (allocation-light per-frame sync).
    binder.sync();
    expect(sink.updates, isEmpty);
    expect(sink.removes, isEmpty);

    // Change → exactly one UPDATE.
    world.getEntity(entity).$1.insert(const Marker('hot'));
    world.flush();
    binder.sync();
    expect(sink.updates, hasLength(1));
    expect(sink.stored.values.single.argb, 0xFFFF4444);

    // Despawn → REMOVE.
    world.getEntity(entity).$1.despawn();
    world.flush();
    binder.sync();
    expect(sink.removes, hasLength(1));
    expect(sink.count, 0);
  });

  test(
    'a spec returning null skips the entity; one spec per type',
    () {
    final world = buildWorld();
    final mapping = SceneMapping()
      ..add<Marker>(
        (entity, marker, world) =>
            marker.kind == 'hidden' ? null : VisualState(
              shape: SceneShape.sphere,
              argb: 0xFFFFFFFF,
              size: 1,
              position: [0, 0, 0],
            ),
      );
    world.spawnComponents([const Marker('hidden')]);
    world.spawnComponents([const Marker('visible')]);
    world.flush();

    expect(mapping.collect(world), hasLength(1));

    // Re-registering replaces (still one spec, still one visual per
    // carrying entity).
    mapping.add<Marker>(
      (entity, marker, world) => VisualState(
        shape: SceneShape.disc,
        argb: 0xFF000000,
        size: 2,
        position: [0, 0, 0],
      ),
    );
    expect(mapping.specCount, 1);
    // The REPLACING spec has no skip — both carriers now get visuals.
    final collected = mapping.collect(world);
    expect(collected, hasLength(2));
    expect(collected.values.every((v) => v.shape == SceneShape.disc), isTrue);
  });
}
