import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:ecsly/ecsly.dart';

import 'camera_projection_mode_resource.dart';

/// Immutable active-camera entry consumed by viewport rendering.
class ActiveCameraEntry {
  /// Creates one active camera record for the current frame.
  const ActiveCameraEntry({
    required this.entity,
    required this.viewport,
    required this.mode,
  });

  /// Camera entity id.
  final Entity entity;

  /// Normalized viewport consumed by host rendering.
  final ViewportRect viewport;

  /// Projection family for this camera.
  final CameraProjectionMode mode;
}

/// Ordered list of (camera entity, viewport rect) for this frame.
/// Filled by [activeCamerasSystem]; host reads this to draw per viewport.
/// Empty or absent = fallback to single active camera, full screen.
class ActiveCamerasResource extends Resource {
  /// Creates an empty per-frame active camera list.
  ActiveCamerasResource();

  /// Ordered active cameras used for this frame.
  final List<ActiveCameraEntry> cameras = [];
}
