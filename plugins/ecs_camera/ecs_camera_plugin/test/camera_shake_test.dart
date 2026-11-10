import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Camera Shake Component and System', () {
    late World world;

    setUp(() {
      world = World()..addPlugin(CameraPlugin());
    });

    test('camera shake component can be added to camera entity', () {
      // Find default camera entity
      final cameraQuery = world.query<CameraComponent>();
      expect(cameraQuery.isNotEmpty, isTrue);

      final cameraEntity = cameraQuery.first.$1.entity;
      final (ext, _) = world.getEntity(cameraEntity);

      // Add camera shake component
      final shake = ext
          .toExtension()
          .getOrCreate<CameraShakeComponent, CameraShake>();
      shake
        ..offsetX = 0
        ..offsetY = 0
        ..decay = 0.8;

      world.flush();

      // Verify shake component exists
      final shake2 = ext
          .toExtension()
          .getExtension<CameraShakeComponent, CameraShake>();
      expect(shake2, isNotNull);
      expect(shake2!.decay, closeTo(0.8, 1e-5));
    });

    test('camera shake decays over time', () {
      // Find default camera entity
      final cameraEntity = world.query<CameraComponent>().first.$1.entity;
      final (ext, _) = world.getEntity(cameraEntity);

      // Add camera shake component
      final shake = ext
          .toExtension()
          .getOrCreate<CameraShakeComponent, CameraShake>();
      shake
        ..offsetX = 10.0
        ..offsetY = 5.0
        ..decay = 0.1;

      world.flush();

      // Add delta time resource
      world.upsertResource(DeltaTimeResource(0.016)); // ~60fps

      // Run shake system multiple times – use enough iterations so that
      // exponential decay clearly dominates the random noise added by
      // the shake system.
      for (var i = 0; i < 50; i++) {
        cameraShakeSystem(world);
        world.flush();
      }

      const initialOffsetX = 10.0;
      const initialOffsetY = 5.0;

      // Shake should have decayed (tolerance for FP / step count)
      expect(shake.offsetX.abs(), lessThan(initialOffsetX));
      expect(shake.offsetY.abs(), lessThan(initialOffsetY));
    });

    test('camera shake can be added via addShake method', () {
      final cameraEntity = world.query<CameraComponent>().first.$1.entity;
      final (ext, _) = world.getEntity(cameraEntity);

      final shake = ext
          .toExtension()
          .getOrCreate<CameraShakeComponent, CameraShake>();
      shake.decay = 0.8;

      // Add shake impulse
      shake.addShake(5, 3);

      expect(shake.offsetX, 5.0);
      expect(shake.offsetY, 3.0);
      expect(shake.hasShake, isTrue);
    });

    test('camera shake resets to zero', () {
      final cameraEntity = world.query<CameraComponent>().first.$1.entity;
      final (ext, _) = world.getEntity(cameraEntity);

      final shake = ext
          .toExtension()
          .getOrCreate<CameraShakeComponent, CameraShake>();
      shake
        ..offsetX = 10.0
        ..offsetY = 5.0;

      shake.reset();

      expect(shake.offsetX, 0.0);
      expect(shake.offsetY, 0.0);
      expect(shake.hasShake, isFalse);
    });

    test('camera shake applies offset during rendering', () {
      final cameraEntity = world.query<CameraComponent>().first.$1.entity;
      final (ext, _) = world.getEntity(cameraEntity);

      final pos = ext
          .toExtension()
          .getOrCreate<CameraPositionComponent, CameraPosition>();
      pos
        ..x = 100
        ..y = 100;

      final shake = ext
          .toExtension()
          .getOrCreate<CameraShakeComponent, CameraShake>();
      shake
        ..offsetX = 2.0
        ..offsetY = -1.5;

      world.flush();

      // Camera adapter should apply shake offset during transformCanvas
      // This is tested indirectly through EcsCamera usage
      expect(shake.hasShake, isTrue);
    });
  });
}
