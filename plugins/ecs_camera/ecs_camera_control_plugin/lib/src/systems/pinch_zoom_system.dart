import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_control_plugin/src/resources/pinch_resource.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';

/// Pinch zoom system that processes PinchEvent for camera zoom with coordinate transformation.
///
/// Tracks pinch gesture state to calculate delta scale from cumulative scale.
/// On RawScaleStartEvent, resets pinch state to each camera's current zoom level.
/// Applies zoom centered on the pinch focal point using proper camera coordinate transformation.
void pinchZoomSystem(final World world) {
  // Check if camera zooming is allowed in current interaction mode
  final modeResource = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;

  if (modeResource == null || !modeResource.allowsCameraZoom) {
    return; // Camera zooming disabled or not allowed in current mode
  }

  // Get or create pinch zoom state resource
  if (!world.resources.has<PinchZoomResource>()) {
    world.resources.push(PinchZoomResource());
  }
  final pinchState = world.getResource<PinchZoomResource>();

  // Get viewport size for coordinate transformation (from camera plugin)
  ui.Size viewportSize = const ui.Size(800, 600);
  // Try to get ViewportSizeResource from camera plugin
  for (final resource in world.resources.iter<ViewportSizeResource>()) {
    viewportSize = ui.Size(resource.width, resource.height);
    break;
  }

  // Process RawScaleStartEvent to reset pinch state for new gestures
  for (final startEvent in world.events.reader<RawScaleStartEvent>().iter()) {
    // Reset state for all cameras to their current zoom levels as gesture baseline
    for (final (cameraEntity, pos, _)
        in world
            .queryExt2<
              CameraPositionComponent,
              CameraPosition,
              CameraConstraints,
              CameraConstraints
            >()) {
      pinchState.setPreviousScale(cameraEntity.entity, pos.zoom);

      // Store the initial world focal point to keep it fixed during the gesture
      final worldFocalPoint = CameraCoordinateUtils.screenToWorldFromComponent(
        startEvent.focalPoint,
        pos,
        viewportSize,
      );
      pinchState.setWorldFocalPoint(cameraEntity.entity, worldFocalPoint);
    }
  }

  // Process RawScaleEndEvent to clean up focal point state
  for (final _ in world.events.reader<RawScaleEndEvent>().iter()) {
    // Clear stored focal points for all cameras
    for (final (cameraEntity, _, _)
        in world
            .queryExt2<
              CameraPositionComponent,
              CameraPosition,
              CameraConstraints,
              CameraConstraints
            >()) {
      pinchState.clearWorldFocalPoint(cameraEntity.entity);
    }
  }

  for (final pinchEvent in world.events.reader<PinchEvent>().iter()) {
    // Apply zoom to all cameras with CameraPosition components
    for (final (cameraEntity, pos, constraints)
        in world
            .queryExt2<
              CameraPositionComponent,
              CameraPosition,
              CameraConstraints,
              CameraConstraints
            >()) {
      // Get previous scale for this camera (set to camera zoom on gesture start)
      final previousScale = pinchState.getPreviousScale(cameraEntity.entity);
      final currentScale = pinchEvent.scale;

      // Calculate new zoom as baseline zoom * cumulative scale from gesture start
      final newZoom = previousScale * currentScale;

      // Only apply zoom if there's a meaningful change
      if ((newZoom - pos.zoom).abs() > 0.001) {
        // Get the fixed world focal point stored at gesture start
        final worldFocalPoint = pinchState.getWorldFocalPoint(
          cameraEntity.entity,
        );
        if (worldFocalPoint == null) continue; // Skip if no focal point stored

        // Get zoom limits from CameraConstraints, fallback to defaults
        final minZoom = constraints.minZoom;
        final maxZoom = constraints.maxZoom;

        // Clamp to limits
        final clampedZoom = newZoom.clamp(minZoom, maxZoom);

        // Calculate screen offset from viewport center to focal point
        final screenOffsetX = pinchEvent.focalPoint.dx - viewportSize.width / 2;
        final screenOffsetY =
            pinchEvent.focalPoint.dy - viewportSize.height / 2;

        // Calculate new camera position to keep the world focal point stationary during zoom
        // This creates the "zoom towards finger" behavior
        // Formula: newCamera = worldFocal - screenOffset / newZoom
        final newCameraX = worldFocalPoint.dx - screenOffsetX / clampedZoom;
        final newCameraY = worldFocalPoint.dy - screenOffsetY / clampedZoom;

        // Apply immediate changes (no smoothing for pinch gestures)
        pos.x = newCameraX;
        pos.y = newCameraY;
        pos.zoom = clampedZoom;

        // Update targets to match current values (prevents smoothing system from overriding)
        pos.targetX = newCameraX;
        pos.targetY = newCameraY;
        pos.targetZoom = clampedZoom;
      }
    }
  }
}
