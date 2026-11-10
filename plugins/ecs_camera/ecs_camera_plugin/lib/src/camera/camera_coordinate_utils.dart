import 'dart:ui' as ui;

import 'components/camera_components.dart';

/// Camera coordinate conversion utilities for ECS camera components.
///
/// Provides functions to convert between screen coordinates (pixels relative to viewport)
/// and world coordinates (logical game world units) using CameraPositionComponent.
class CameraCoordinateUtils {
  /// Private constructor to prevent instantiation.
  CameraCoordinateUtils._();

  /// Convert screen coordinates to world coordinates using CameraPosition component.
  ///
  /// New component-based API. Prefer this over the resource-based version.
  static ui.Offset screenToWorldFromComponent(
    final ui.Offset screenPos,
    final CameraPosition camera,
    final ui.Size viewportSize,
  ) {
    final worldX =
        camera.x + (screenPos.dx - viewportSize.width / 2) / camera.zoom;
    final worldY =
        camera.y + (screenPos.dy - viewportSize.height / 2) / camera.zoom;
    return ui.Offset(worldX, worldY);
  }

  /// Convert world coordinates to screen coordinates using CameraPosition component.
  ///
  /// New component-based API. Prefer this over the resource-based version.
  /// Matches the transformation logic in EcsCamera.transformCanvas().
  static ui.Offset worldToScreenFromComponent(
    final ui.Offset worldPos,
    final CameraPosition camera,
    final ui.Size viewportSize,
  ) {
    // Transform: (world - camera) * zoom + viewportCenter
    final screenX =
        (worldPos.dx - camera.x) * camera.zoom + viewportSize.width / 2;
    final screenY =
        (worldPos.dy - camera.y) * camera.zoom + viewportSize.height / 2;
    return ui.Offset(screenX, screenY);
  }
}
