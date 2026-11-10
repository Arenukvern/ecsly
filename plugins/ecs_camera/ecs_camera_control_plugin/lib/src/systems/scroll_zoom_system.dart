import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';

/// Direct scroll zoom system that processes ScrollEvent and applies zoom to cameras.
///
/// Bypasses InputActionEvent system for immediate scroll-to-zoom response.
/// Applies zoom delta directly to camera position based on scroll direction.
/// Zooms towards the cursor position (scroll focal point).
void scrollZoomSystem(final World world) {
  // Check if camera zooming is allowed in current interaction mode
  final modeResource = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;

  if (modeResource == null || !modeResource.allowsCameraZoom) {
    return; // Camera zooming disabled or not allowed in current mode
  }

  // Get viewport size for coordinate transformation
  ui.Size viewportSize = const ui.Size(800, 600);
  for (final resource in world.resources.iter<ViewportSizeResource>()) {
    viewportSize = ui.Size(resource.width, resource.height);
    break;
  }

  for (final scrollEvent in world.events.reader<ScrollEvent>().iter()) {
    // Apply zoom to all cameras with CameraPosition components
    for (final (entity, pos)
        in world.queryExt<CameraPositionComponent, CameraPosition>()) {
      // Get zoom limits from CameraConstraints, fallback to defaults
      final (minZoom, maxZoom) = getCameraZoomConstraints(world, entity.entity);

      // Calculate zoom factor based on scroll direction
      // Negative delta (scroll up) = zoom in, positive delta (scroll down) = zoom out
      final zoomFactor = scrollEvent.delta.dy < 0
          ? 1.05
          : 0.95; // 5% zoom per scroll

      // Calculate new zoom
      final newZoom = (pos.zoom * zoomFactor).clamp(minZoom, maxZoom);

      // Only apply if there's a meaningful change
      if ((newZoom - pos.zoom).abs() < 0.001) continue;

      // Transform scroll position to world coordinates for zoom centering
      final worldFocalPoint = CameraCoordinateUtils.screenToWorldFromComponent(
        scrollEvent.position,
        pos,
        viewportSize,
      );

      // Calculate screen offset from viewport center to scroll position
      final screenOffsetX = scrollEvent.position.dx - viewportSize.width / 2;
      final screenOffsetY = scrollEvent.position.dy - viewportSize.height / 2;

      // Calculate new camera position to keep the world focal point stationary during zoom
      // Formula: newCamera = worldFocal - screenOffset / newZoom
      final newCameraX = worldFocalPoint.dx - screenOffsetX / newZoom;
      final newCameraY = worldFocalPoint.dy - screenOffsetY / newZoom;

      // Apply immediate changes (no smoothing for scroll gestures)
      pos.x = newCameraX;
      pos.y = newCameraY;
      pos.zoom = newZoom;

      // Update targets to match current values (prevents smoothing system from overriding)
      pos.targetX = newCameraX;
      pos.targetY = newCameraY;
      pos.targetZoom = newZoom;
    }
  }
}
