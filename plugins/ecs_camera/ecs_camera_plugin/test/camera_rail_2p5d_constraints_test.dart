import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cameraRail2p5DConstraintsSystem', () {
    test('clamps x/y/z, yaw/pitch and fov', () {
      final world = World()..addPlugin(CameraPlugin());
      world.flush();

      final entity = world.query<CameraComponent>().first.$1.entity;
      world.upsertComponent(
        entity,
        const CameraRail2p5DConstraints(
          minX: -12,
          maxX: 12,
          fixedY: 4,
          fixedZ: 18,
          minYawDeg: -5,
          maxYawDeg: 5,
          fixedPitchDeg: -10,
          minFov: 35,
          maxFov: 50,
        ),
      );
      world.flush();

      final (ext, exists) = world.getEntityExtension(entity);
      expect(exists, isTrue);

      final pos = ext.getExtension<CameraPositionComponent, CameraPosition>()!;
      final pose = ext.getExtension<CameraPose3Component, CameraPose3>()!;
      pos
        ..x = 100.0
        ..targetX = -100.0
        ..y = -25.0
        ..targetY = 30.0
        ..zoom = 70.0
        ..targetZoom = 70.0;
      pose
        ..posZ = -7.0
        ..zoomOrFovOverride = 100.0;
      final seedQuat = yawPitchDegreesToQuaternion(yawDeg: 16, pitchDeg: 19);
      pose
        ..rotX = seedQuat.x
        ..rotY = seedQuat.y
        ..rotZ = seedQuat.z
        ..rotW = seedQuat.w;

      cameraRail2p5DConstraintsSystem(world);

      expect(pos.x, closeTo(12.0, 1e-6));
      expect(pos.targetX, closeTo(-12.0, 1e-6));
      expect(pos.y, closeTo(4.0, 1e-6));
      expect(pos.targetY, closeTo(4.0, 1e-6));
      expect(pose.posZ, closeTo(18.0, 1e-6));

      final angles = quaternionToYawPitchDegrees(
        x: pose.rotX,
        y: pose.rotY,
        z: pose.rotZ,
        w: pose.rotW,
      );
      expect(angles.yawDeg, closeTo(5.0, 1e-6));
      expect(angles.pitchDeg, closeTo(-10.0, 1e-6));
      expect(pose.zoomOrFovOverride, closeTo(50.0, 1e-6));
      expect(pos.zoom, closeTo(50.0, 1e-6));
      expect(pos.targetZoom, closeTo(50.0, 1e-6));
    });
  });

  group('camera_orientation_math', () {
    test('yaw/pitch quaternion round-trips deterministically', () {
      const cases = <(double, double)>[
        (-5.0, -8.0),
        (0.0, 0.0),
        (4.5, -12.0),
        (5.0, 9.0),
      ];

      for (final (yaw, pitch) in cases) {
        final quat = yawPitchDegreesToQuaternion(yawDeg: yaw, pitchDeg: pitch);
        final angles = quaternionToYawPitchDegrees(
          x: quat.x,
          y: quat.y,
          z: quat.z,
          w: quat.w,
        );
        expect(angles.yawDeg, closeTo(yaw, 1e-6));
        expect(angles.pitchDeg, closeTo(pitch, 1e-6));
      }
    });

    test('normalizeQuaternion returns identity for invalid inputs', () {
      final invalid = normalizeQuaternion(
        x: double.nan,
        y: double.infinity,
        z: 0,
        w: 0,
      );
      expect(invalid.x, 0.0);
      expect(invalid.y, 0.0);
      expect(invalid.z, 0.0);
      expect(invalid.w, 1.0);
    });
  });
}
