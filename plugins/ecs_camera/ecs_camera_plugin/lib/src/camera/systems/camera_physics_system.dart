import 'package:ecsly/ecsly.dart';

import '../components/camera_components.dart';

/// Camera physics system - applies velocity (momentum).
///
/// Updates camera position based on velocity and applies damping.
/// Requires CameraPosition and CameraVelocity components.
/// For FreeTarget cameras, syncs target position to current position
/// to prevent smoothing systems from pulling camera back.
void cameraPhysicsSystem(final World world) {
  final dt = world.getResource<DeltaTimeResource>().deltaTime;

  for (final (entity, pos, vel)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            CameraVelocityComponent,
            CameraVelocity
          >()) {
    pos.x += vel.dx * dt;
    pos.y += vel.dy * dt;

    // Apply damping
    vel.dx *= vel.damping;
    vel.dy *= vel.damping;

    // Stop very small velocities
    if (vel.dx.abs() < 0.01) vel.dx = 0.0;
    if (vel.dy.abs() < 0.01) vel.dy = 0.0;

    // Sync target position for FreeTarget cameras
    // This prevents smoothing/lerp systems from pulling camera back to old position
    final entityObj = entity.toEntity();
    if (entityObj.get<FreeTarget>() != null) {
      pos.targetX = pos.x;
      pos.targetY = pos.y;
    }
  }
}
