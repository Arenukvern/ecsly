import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../components/camera_action_components.dart';
import '../resources/camera_interaction_mode_resource.dart';

/// Generic camera pan system driven by CameraPanAction component.
///
/// Supports both keyboard-based panning (WASD) and drag-based panning (mouse/touch).
/// Drag panning accumulates deltas from DragEvent events when camera pan action is active.
/// Keyboard panning uses axis-based input from InputStateTracker.
void genericCameraPanSystem(final World world) {
  // Graceful exit if InputPlugin not installed
  if (!world.resources.has<InputStateTracker>()) {
    return;
  }

  // Check if camera panning is allowed in current interaction mode
  final modeResource = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;

  if (modeResource == null || !modeResource.allowsCameraPan) {
    return; // Camera panning disabled or not allowed in current mode
  }

  final actionTracker = world.getResource<InputStateTracker>();
  final dragReader = world.events.reader<DragEvent>();
  final tracker = world.resources.has<GestureConsumptionTracker>()
      ? world.getResource<GestureConsumptionTracker>()
      : null;

  for (final (entity, panAction)
      in world.queryExt<CameraPanAction, CameraPanAction>()) {
    // Find the corresponding camera position and velocity
    final pos = entity.getExtension<CameraPositionComponent, CameraPosition>();
    final vel = entity.getExtension<CameraVelocityComponent, CameraVelocity>();
    if (pos == null || vel == null) continue;

    // Get keyboard input first to check if there's any input
    // Negate Y to fix up/down inversion (screen Y increases downward, but up should move camera up)
    final rawKeyboardInput = actionTracker.getAxis2D(
      InputAction.moveUp,
      InputAction.moveDown,
      InputAction.moveLeft,
      InputAction.moveRight,
    );
    final keyboardInput = (rawKeyboardInput.$1, -rawKeyboardInput.$2);
    final hasKeyboardInput = keyboardInput.$1 != 0.0 || keyboardInput.$2 != 0.0;

    // Determine input source: check for drag events and trigger state
    final hasDragEvents = dragReader.iter().isNotEmpty;

    // Determine if drag input should be used:
    // - If trigger is null: allow drag without trigger check (triggerless = always active)
    // - If trigger is set: require trigger to be held for drag
    final isDragTriggerActive = panAction.trigger == null
        ? true // Triggerless: always allow drag
        : actionTracker.isHeld(
            panAction.trigger!,
          ); // With trigger: require it to be held
    final isDragInput = hasDragEvents && isDragTriggerActive;

    // Determine which input to use: prefer drag if available and allowed, otherwise keyboard
    // For triggerless actions: process keyboard first, drag second (if available)
    // For triggered actions: process drag if trigger held, keyboard as fallback
    final (dx, dy) = isDragInput
        ? _calculateDragPanDelta(dragReader, tracker, panAction, pos.zoom)
        : keyboardInput;

    // Skip if no input (neither keyboard nor drag)
    if (!hasKeyboardInput && !isDragInput) {
      continue;
    }

    // Skip if calculated delta is zero (e.g., all drag events were consumed)
    if (dx == 0.0 && dy == 0.0) continue;

    // Apply pan based on mode
    switch (panAction.mode) {
      case PanMode.world:
      case PanMode.screen:
      case PanMode.velocity:
        if (isDragInput) {
          // Direct position modification for 1:1 drag control
          // Drag deltas are already in world space (pixels/frame)
          // Apply directly to position for instant, precise cursor tracking
          pos.x += dx * panAction.speed;
          pos.y += dy * panAction.speed;
          // Update target to prevent smoothing systems from pulling camera back
          pos.targetX = pos.x;
          pos.targetY = pos.y;
          // Clear velocity to prevent momentum accumulation
          vel.dx = 0;
          vel.dy = 0;
        } else {
          // Keyboard input: also use direct position update for instant response
          // Bypasses velocity/damping system to match drag feel
          // Get move speed from CameraController if available, otherwise use panAction.speed
          final controller = entity.toEntity().get<CameraController>();
          final moveSpeed = controller?.moveSpeed ?? (panAction.speed * 400.0);

          // Convert axis input (-1 to 1) to frame delta (pixels/frame)
          final dt = world.getResource<DeltaTimeResource>().deltaTime;
          pos.x += dx * moveSpeed * dt;
          pos.y += dy * moveSpeed * dt;

          // Update target to prevent smoothing systems from pulling camera back
          pos.targetX = pos.x;
          pos.targetY = pos.y;

          // Clear velocity to prevent damping from interfering
          vel.dx = 0;
          vel.dy = 0;
        }
    }
  }
}

/// Calculate pan delta from accumulated drag events.
///
/// [dragReader] Reader for DragEvent events
/// [tracker] Gesture consumption tracker (may be null)
/// [panAction] Camera pan action configuration
/// [zoom] Current camera zoom level
/// Returns accumulated (dx, dy) delta for camera movement
(double, double) _calculateDragPanDelta(
  final EventReader<DragEvent> dragReader,
  final GestureConsumptionTracker? tracker,
  final CameraPanAction panAction,
  final double zoom,
) {
  var totalDx = 0.0;
  var totalDy = 0.0;

  // Accumulate deltas from all drag events
  for (final dragEvent in dragReader.iter()) {
    // Skip if event was already consumed (e.g., by entity dragging)
    if (tracker != null && tracker.isDragConsumed(dragEvent)) {
      continue;
    }

    // Apply zoom correction to convert screen delta to world delta
    // Negate delta to match "grab and pull viewport" metaphor:
    // dragging right should move camera left (show content to the right)
    totalDx += -dragEvent.delta.dx / zoom;
    totalDy += -dragEvent.delta.dy / zoom;
  }

  return (totalDx, totalDy);
}
