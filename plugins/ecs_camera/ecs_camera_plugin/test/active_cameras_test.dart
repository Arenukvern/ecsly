import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActiveCamerasResource and activeCamerasSystem', () {
    late World world;

    setUp(() {
      world = World()..addPlugin(CameraPlugin());
    });

    test('single active camera is filled with fullScreen viewport', () {
      world.flush();
      activeCamerasSystem(world);
      final resource = world.getResource<ActiveCamerasResource>();
      expect(resource.cameras.length, equals(1));
      expect(resource.cameras.first.viewport.x, equals(0));
      expect(resource.cameras.first.viewport.w, equals(1));
      expect(
        resource.cameras.first.mode,
        equals(CameraProjectionMode.orthographic2d),
      );
    });

    test('second camera with custom viewport appears in order', () {
      final e = world.entities.create();
      world.spawnBundle(
        e,
        ComponentBundle.fromLists([
          CameraComponent(priority: -1),
          CameraViewportRectComponent(
            viewport: const ViewportRect(x: 0.5, w: 0.5),
          ),
        ], []),
      );
      world.flush();
      activeCamerasSystem(world);
      final resource = world.getResource<ActiveCamerasResource>();
      expect(resource.cameras.length, equals(2));
      expect(resource.cameras.first.viewport.w, equals(1));
      expect(resource.cameras[1].viewport.x, equals(0.5));
      expect(resource.cameras[1].viewport.w, equals(0.5));
    });

    test('inactive camera is excluded', () {
      final cameraEntity = world.query<CameraComponent>().first.$1.entity;
      final (we, _) = world.getEntity(cameraEntity);
      we.get<CameraComponent>()!.isActive = false;
      world.flush();
      activeCamerasSystem(world);
      final resource = world.getResource<ActiveCamerasResource>();
      expect(resource.cameras.length, equals(0));
    });
  });
}
