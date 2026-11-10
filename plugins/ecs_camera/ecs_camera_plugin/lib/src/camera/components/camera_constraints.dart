import 'package:ecsly/ecsly.dart';

import 'camera_components.dart';

/// Camera constraints component.
///
/// Limits camera position and zoom to specified bounds.
/// Attach to camera entities that need boundary constraints.
class CameraConstraints extends Component {
  /// Creates camera world and zoom constraints.
  CameraConstraints({
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    this.minZoom = 0.1,
    this.maxZoom = 5.0,
    this.maxFollowDistance,
  });

  /// Minimum X position (world coordinates)
  final double? minX;

  /// Maximum X position (world coordinates)
  final double? maxX;

  /// Minimum Y position (world coordinates)
  final double? minY;

  /// Maximum Y position (world coordinates)
  final double? maxY;

  /// Minimum zoom level
  final double minZoom;

  /// Maximum zoom level
  final double maxZoom;

  /// Maximum distance camera can be from follow target
  /// (for follow behaviors only)
  final double? maxFollowDistance;

  /// Constrain position and zoom to bounds.
  /// Clamps both current and target values to ensure consistency.
  void constrainPosition(final CameraPosition pos) {
    // Clamp target position
    if (minX != null || maxX != null) {
      pos.targetX = pos.targetX.clamp(
        minX ?? double.negativeInfinity,
        maxX ?? double.infinity,
      );
    }
    if (minY != null || maxY != null) {
      pos.targetY = pos.targetY.clamp(
        minY ?? double.negativeInfinity,
        maxY ?? double.infinity,
      );
    }

    // Clamp target zoom
    pos.targetZoom = pos.targetZoom.clamp(minZoom, maxZoom);

    // Also clamp current position (for immediate feedback)
    if (minX != null || maxX != null) {
      pos.x = pos.x.clamp(
        minX ?? double.negativeInfinity,
        maxX ?? double.infinity,
      );
    }
    if (minY != null || maxY != null) {
      pos.y = pos.y.clamp(
        minY ?? double.negativeInfinity,
        maxY ?? double.infinity,
      );
    }

    // Clamp current zoom
    pos.zoom = pos.zoom.clamp(minZoom, maxZoom);
  }
}
