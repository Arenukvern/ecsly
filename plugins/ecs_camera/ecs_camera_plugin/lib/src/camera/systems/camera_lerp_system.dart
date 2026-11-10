import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';

import '../components/camera_components.dart';

/// Camera smoothing system - smoothly interpolates camera to target position/zoom.
///
/// Uses exponential interpolation for natural movement.
/// Smoothly interpolates camera position and zoom towards their target values.
/// Requires CameraPosition and CameraSmoothing components.
void cameraSmoothingSystem(final World world) {
  final dt = world.getResource<DeltaTimeResource>().deltaTime;

  // Query all active cameras with smoothing
  for (final (_, pos, smoothing)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            CameraSmoothing,
            CameraSmoothing
          >()) {
    // Exponential interpolation: 1.0 - exp(-speed * dt)
    final posLerpFactor = 1.0 - math.exp(-smoothing.positionSpeed * dt);
    final zoomLerpFactor = 1.0 - math.exp(-smoothing.zoomSpeed * dt);

    pos.x = pos.x + (pos.targetX - pos.x) * posLerpFactor;
    pos.y = pos.y + (pos.targetY - pos.y) * posLerpFactor;
    pos.zoom = pos.zoom + (pos.targetZoom - pos.zoom) * zoomLerpFactor;
  }
}
