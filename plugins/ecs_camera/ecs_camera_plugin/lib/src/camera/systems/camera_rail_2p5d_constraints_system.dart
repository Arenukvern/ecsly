import 'package:ecsly/ecsly.dart';

import '../camera_orientation_math.dart';
import '../components/camera_components.dart';

/// Applies deterministic 2.5D rail clamps for cinematic side-view cameras.
void cameraRail2p5DConstraintsSystem(final World world) {
  for (final (_, pos, pose, constraints)
      in world
          .queryExt3<
            CameraPositionComponent,
            CameraPosition,
            CameraPose3Component,
            CameraPose3,
            CameraRail2p5DConstraints,
            CameraRail2p5DConstraints
          >()) {
    final minX = constraints.minX;
    final maxX = constraints.maxX;
    final minYawDeg = constraints.minYawDeg;
    final maxYawDeg = constraints.maxYawDeg;
    final minFov = constraints.minFov;
    final maxFov = constraints.maxFov;

    pos.x = pos.x.clamp(minX, maxX);
    pos.targetX = pos.targetX.clamp(minX, maxX);
    pos.y = constraints.fixedY;
    pos.targetY = constraints.fixedY;

    pose.posZ = constraints.fixedZ;

    final angles = quaternionToYawPitchDegrees(
      x: pose.rotX,
      y: pose.rotY,
      z: pose.rotZ,
      w: pose.rotW,
    );
    final clampedYaw = angles.yawDeg.clamp(minYawDeg, maxYawDeg);
    final clampedQuat = yawPitchDegreesToQuaternion(
      yawDeg: clampedYaw,
      pitchDeg: constraints.fixedPitchDeg,
    );
    pose.rotX = clampedQuat.x;
    pose.rotY = clampedQuat.y;
    pose.rotZ = clampedQuat.z;
    pose.rotW = clampedQuat.w;

    final currentFov =
        pose.zoomOrFovOverride.isFinite && pose.zoomOrFovOverride > 0
        ? pose.zoomOrFovOverride
        : pos.zoom;
    final clampedFov = currentFov.clamp(minFov, maxFov);
    pose.zoomOrFovOverride = clampedFov;
    pos.zoom = clampedFov;
    pos.targetZoom = clampedFov;
  }
}
