import 'package:ecsly/ecsly.dart';
import '../../../ecs_camera_plugin.dart';

/// Get current camera zoom level, defaulting to 1.0 if camera not available.
///
/// Searches for the first active camera with CameraPositionComponent.
/// Used by systems that need to scale movements based on current zoom level.
double getCameraZoom(final World world) {
  try {
    for (final (entity, pos)
        in world.queryExt<CameraPositionComponent, CameraPosition>()) {
      final (ext, valid) = world.getEntity(entity.entity);
      if (!valid) continue;

      final camera = ext.get<CameraComponent>();
      if (camera != null && camera.isActive) {
        return pos.zoom;
      }
    }
  } on Object catch (_) {
    // Camera plugin not available - graceful fallback
  }

  return 1; // Default when camera not available
}

/// Extract zoom constraints from a camera entity.
///
/// Returns (minZoom, maxZoom) tuple with fallback defaults if no constraints exist.
/// This centralizes the zoom constraint extraction logic used across multiple camera systems.
(double, double) getCameraZoomConstraints(
  final World world,
  final Entity cameraEntity,
) {
  final (worldEntity, valid) = world.getEntity(cameraEntity);
  if (!valid) return (0.1, 10.0); // Fallback defaults

  final constraints = worldEntity.get<CameraConstraints>();
  final minZoom = constraints?.minZoom ?? 0.1;
  final maxZoom = constraints?.maxZoom ?? 10.0;

  return (minZoom, maxZoom);
}
