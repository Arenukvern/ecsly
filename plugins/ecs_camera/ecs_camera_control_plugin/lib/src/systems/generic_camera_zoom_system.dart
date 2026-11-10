import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../components/camera_action_components.dart';
import '../resources/camera_interaction_mode_resource.dart';

/// Generic camera zoom system driven by CameraZoomAction component.
///
/// Uses frame-rate independent calculations with deltaTime for consistent zoom speed
/// regardless of FPS. Supports both linear and exponential zoom modes.
void genericCameraZoomSystem(final World world) {
  // Graceful exit if InputPlugin not installed
  if (!world.resources.has<InputStateTracker>()) {
    return;
  }

  // Check if camera zooming is allowed in current interaction mode
  final modeResource = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;

  if (modeResource == null || !modeResource.allowsCameraZoom) {
    return; // Camera zooming disabled or not allowed in current mode
  }

  final actionTracker = world.getResource<InputStateTracker>();

  // Get deltaTime for frame-rate independent zoom
  final dt = world.resources.has<DeltaTimeResource>()
      ? world.getResource<DeltaTimeResource>().deltaTime
      : 1.0 / 60.0; // Fallback to 60 FPS if deltaTime not available

  for (final (entity, zoomAction)
      in world.queryExt<CameraZoomAction, CameraZoomAction>()) {
    // Find the corresponding camera position
    final pos = entity.getExtension<CameraPositionComponent, CameraPosition>();
    if (pos == null) continue;

    // Check both zoomIn and zoomOut actions, regardless of component trigger
    // This allows a single component to handle both directions
    // (ECS only allows one component of each type per entity, so when preset bundle
    // contains both CameraZoomAction(zoomIn) and CameraZoomAction(zoomOut), the second overwrites the first)
    final zoomInActive = actionTracker.isHeld(InputAction.zoomIn);
    final zoomOutActive = actionTracker.isHeld(InputAction.zoomOut);

    if (!zoomInActive && !zoomOutActive) continue;

    // Calculate combined zoom delta from both actions
    // Positive = zoom in, negative = zoom out
    final zoomInDelta = zoomInActive
        ? actionTracker.getAxis(InputAction.zoomIn)
        : 0.0;
    final zoomOutDelta = zoomOutActive
        ? -actionTracker.getAxis(InputAction.zoomOut)
        : 0.0;
    final zoomDelta = zoomInDelta + zoomOutDelta;

    if (zoomDelta == 0.0) continue;

    // Get zoom limits from CameraConstraints, fallback to defaults
    final (minZoom, maxZoom) = getCameraZoomConstraints(world, entity.entity);

    // Use current zoom (pos.zoom) as base for calculations, not targetZoom
    // This ensures we're zooming from the actual current zoom level
    final currentZoom = pos.zoom;

    // Apply zoom based on mode (frame-rate independent)
    // Speed is in units per second, so multiply by deltaTime
    final newZoom = switch (zoomAction.mode) {
      ZoomMode.linear => currentZoom + zoomDelta * zoomAction.speed * dt,
      ZoomMode.exponential =>
        // Exponential: zoom by factor per second, scaled by deltaTime
        // Base factor of 2.0 per second means zoom doubles in 1 second at speed=1.0
        // Formula: zoom * (base_factor ^ (speed * dt))
        // With speed=1.0, dt=1/60: zoom * (2.0 ^ (1/60)) ≈ zoom * 1.0116 (1.16% per frame)
        // This gives responsive, noticeable zoom that feels natural
        currentZoom * math.pow(2.0, zoomDelta * zoomAction.speed * dt),
    };

    // Clamp to limits
    final clampedZoom = newZoom.clamp(minZoom, maxZoom);

    // Set both current zoom and target zoom for immediate effect
    // This matches the behavior of scroll_zoom_system and pinch_zoom_system
    pos.zoom = clampedZoom;
    pos.targetZoom = clampedZoom;
  }
}
