import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless proof of the renderer-agnostic orbit control: ECS input events
/// (the same DragEvent/ScrollEvent that UnifiedInputWidget emits from raw
/// Flutter pointers) drive an [OrbitCameraResource] with NO renderer present.
/// This is the "controls don't depend on flutter_scene" half — a flutter_scene
/// bridge only has to read OrbitCameraResource.cameraPosition() each frame.
void main() {
  late World world;
  late OrbitCameraResource cam;

  DragEvent drag(double dx, double dy, {int buttons = kOrbitPrimaryButton}) =>
      DragEvent(
        position: Offset.zero,
        worldPosition: Offset.zero,
        startPosition: Offset.zero,
        startWorldPosition: Offset.zero,
        delta: Offset(dx, dy),
        timestamp: 0,
        buttons: buttons,
      );

  ScrollEvent scroll(double dy) => ScrollEvent(
    position: Offset.zero,
    worldPosition: Offset.zero,
    delta: Offset(0, dy),
    timestamp: 0,
  );

  setUp(() {
    world = World();
    world.systems.plugins.add(const InputPlugin(), world);
    cam = OrbitCameraResource(
      yaw: 0,
      pitch: 0.5,
      distance: 20,
      targetX: 0,
      targetY: 0,
      targetZ: 0,
    );
    world.upsertResource(cam);
    world.flush();
  });

  group('orbitCameraControlSystem — drag', () {
    test('left-drag pans the target (grab-the-world)', () {
      // yaw 0: screen-right is world -X under flutter_scene's left-handed
      // render, so a grab-the-world drag right moves the target toward +X.
      world.events.writer<DragEvent>().send(drag(10, 0));
      orbitCameraControlSystem(world);
      expect(cam.targetX, greaterThan(0));
      expect(cam.targetZ, closeTo(0, 1e-9));
      expect(cam.yaw, 0, reason: 'a plain drag pans, it does not orbit');
    });

    test('middle-button drag orbits yaw instead of panning', () {
      world.events
          .writer<DragEvent>()
          .send(drag(10, 0, buttons: kOrbitMiddleButton));
      orbitCameraControlSystem(world);
      expect(cam.yaw, greaterThan(0), reason: 'drag right spins yaw +');
      expect(cam.targetX, 0, reason: 'orbit does not translate the target');
    });

    test('middle-button vertical drag tilts pitch (clamped)', () {
      world.events
          .writer<DragEvent>()
          .send(drag(0, 10, buttons: kOrbitMiddleButton));
      orbitCameraControlSystem(world);
      expect(cam.pitch, lessThan(0.5), reason: 'drag down lowers pitch');
      // Clamp holds at the straight-down singularity guard.
      for (var i = 0; i < 400; i++) {
        world.events
            .writer<DragEvent>()
            .send(drag(0, 100, buttons: kOrbitMiddleButton));
        orbitCameraControlSystem(world);
      }
      expect(cam.pitch, greaterThanOrEqualTo(cam.minPitch));
    });
  });

  group('orbitCameraControlSystem — scroll', () {
    // Each test uses the fresh world from setUp and a single system run, so
    // the event buffer holds exactly one scroll (in-game the Input schedule's
    // cleanup drains events every frame; calling the system twice without a
    // frame boundary would otherwise re-process the same event).
    test('scroll up dollies in', () {
      world.events.writer<ScrollEvent>().send(scroll(-100));
      orbitCameraControlSystem(world);
      expect(cam.distance, lessThan(20));
    });

    test('scroll down dollies out', () {
      world.events.writer<ScrollEvent>().send(scroll(100));
      orbitCameraControlSystem(world);
      expect(cam.distance, greaterThan(20));
    });

    test('distance stays within clamps', () {
      for (var i = 0; i < 200; i++) {
        world.events.writer<ScrollEvent>().send(scroll(-100));
      }
      orbitCameraControlSystem(world);
      expect(cam.distance, greaterThanOrEqualTo(cam.minDistance));
    });
  });

  group('orbitCameraControlSystem — mode gating', () {
    test('cinematic mode ignores manual camera input', () {
      world.upsertResource(
        CameraInteractionModeResource(mode: CameraInteractionMode.cinematic),
      );
      world.flush();
      world.events
          .writer<DragEvent>()
          .send(drag(10, 10, buttons: kOrbitMiddleButton));
      world.events.writer<ScrollEvent>().send(scroll(-100));
      orbitCameraControlSystem(world);
      expect(cam.yaw, 0);
      expect(cam.distance, 20);
    });

    test('editor mode allows navigation', () {
      world.upsertResource(
        CameraInteractionModeResource(mode: CameraInteractionMode.editor),
      );
      world.flush();
      world.events
          .writer<DragEvent>()
          .send(drag(10, 0, buttons: kOrbitMiddleButton));
      orbitCameraControlSystem(world);
      expect(cam.yaw, greaterThan(0));
    });
  });

  group('OrbitCameraResource math (renderer bridge surface)', () {
    test('cameraPosition is spherical around the target', () {
      cam
        ..yaw = 0
        ..pitch = 0
        ..distance = 10
        ..targetX = 0
        ..targetY = 0
        ..targetZ = 0;
      final eye = cam.cameraPosition();
      // yaw 0, pitch 0 → eye straight out along +Z at the distance.
      expect(eye.x, closeTo(0, 1e-9));
      expect(eye.y, closeTo(0, 1e-9));
      expect(eye.z, closeTo(10, 1e-9));
    });

    test('zoomAt slides the target toward the cursor world point', () {
      cam
        ..distance = 20
        ..targetX = 0
        ..targetY = 0
        ..targetZ = 0;
      cam.zoomAt(0.5, 10, 0, 10); // zoom in, cursor over world (10,0,10)
      expect(cam.distance, closeTo(10, 1e-9));
      // keep = 1 - 10/20 = 0.5 → target moves halfway to the cursor point.
      expect(cam.targetX, closeTo(5, 1e-9));
      expect(cam.targetZ, closeTo(5, 1e-9));
    });

    test('no OrbitCameraResource → system is a safe no-op', () {
      final bare = World();
      bare.systems.plugins.add(const InputPlugin(), bare);
      bare.flush();
      bare.events.writer<DragEvent>().send(drag(10, 0));
      expect(() => orbitCameraControlSystem(bare), returnsNormally);
    });
  });
}
