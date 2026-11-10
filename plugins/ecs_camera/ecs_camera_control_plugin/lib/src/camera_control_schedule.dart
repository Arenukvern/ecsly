import 'package:ecsly/ecsly.dart';

import 'systems/entity_dragging_system.dart';
import 'systems/generic_camera_pan_system.dart';
import 'systems/generic_camera_zoom_system.dart';
import 'systems/input_world_space_sync_system.dart';
import 'systems/pinch_zoom_system.dart';
import 'systems/scroll_to_zoom_action_system.dart';
import 'systems/scroll_zoom_system.dart';

/// Configures camera control systems in appropriate schedules.
///
/// Systems are distributed across schedules based on their input type:
/// - **KeyboardInput schedule** (runs every frame): Keyboard-based zoom for continuous input
/// - **Input schedule** (event-driven): Gesture-based systems (pan, scroll, pinch)
///
/// Execution order:
/// 1. KeyboardInput: Keyboard state processing → Keyboard zoom
/// 2. Input: Gesture events → Pan, scroll zoom, pinch zoom
/// 3. Camera schedule: Target systems, smoothing, physics, constraints
///
/// **CRITICAL:** For gesture-based features (pinch zoom, drag pan, scroll zoom) to work,
/// you must wrap your widget tree with `UnifiedInputWidget`:
/// ```dart
/// UnifiedInputWidget(
///   world: world,
///   child: GameLoopWidget(
///     world: world,
///     child: YourGameContent(),
///   ),
/// )
/// ```
/// Without `UnifiedInputWidget`, gesture events will not be captured and sent to the ECS.
///
/// **Performance Note:** Keyboard zoom runs every frame in KeyboardInput schedule to support
/// continuous input (key held). This is efficient as it uses simple state checks with early exits.
/// Gesture-based systems run in event-driven Input schedule for zero overhead when inactive.
///
/// Note: Camera target and update systems should be added separately by camera plugin
/// or manually. This function only adds the control systems.
///
/// [world] ECS world
/// [enablePan] Whether to enable camera panning via input
/// [enableZoom] Whether to enable camera zooming via input
/// [enableScrollZoom] Whether to enable scroll-to-zoom
/// [enablePinchZoom] Whether to enable pinch-to-zoom
/// [enableScrollToZoomAction] Whether to enable scroll-to-zoom via InputActionEvent
/// [enableEntityDragging] Whether to enable entity dragging (requires InputPlugin)
void configureCameraControlSchedule(
  final World world, {
  final bool enablePan = true,
  final bool enableZoom = true,
  final bool enableScrollZoom = true,
  final bool enablePinchZoom = true,
  final bool enableScrollToZoomAction = false,
  final bool enableEntityDragging = false,
}) {
  if (!world.hasSchedule(const ScheduleId('Input'))) {
    throw StateError(
      'Input schedule not found. Ensure InputPlugin is installed and configureSchedule is true.',
    );
  }

  final inputSchedule = world.schedule(const ScheduleId('Input'));
  // Sync camera/mode into InputWorldSpaceResource before selection systems read it
  inputSchedule.add(
    inputWorldSpaceSyncSystem,
    name: 'inputWorldSpaceSyncSystem',
    runBefore: ['entitySelectionSystem'],
  );

  // Keyboard zoom needs to run every frame for continuous input (key held)
  // Add to KeyboardInput schedule which runs every frame
  if (enableZoom) {
    if (world.hasSchedule(const ScheduleId('KeyboardInput'))) {
      // Add to KeyboardInput schedule after inputBindingSystem
      // This ensures InputStateTracker is updated before we read it
      // The system will run every frame, allowing continuous zoom while key is held
      // We add it before inputCleanupSystem (which is already in the schedule)
      // by using then() to chain after the last system, or add() to insert before cleanup
      final keyboardSchedule = world.schedule(const ScheduleId('KeyboardInput'));
      // Add with explicit ordering: after inputBindingSystem, before cleanup
      // Since systems are added in order and cleanup is last, this will work correctly
      keyboardSchedule.add(genericCameraZoomSystem);
    } else {
      // Fallback: add to Input schedule if KeyboardInput doesn't exist
      // This will only work on key press events, not continuous hold
      inputSchedule.add(genericCameraZoomSystem);
    }
  }

  // Pan system handles both keyboard (needs every frame) and drag (event-driven)
  if (enablePan) {
    // Add to KeyboardInput schedule for continuous keyboard input (WASD/arrows)
    if (world.hasSchedule(const ScheduleId('KeyboardInput'))) {
      final keyboardSchedule = world.schedule(const ScheduleId('KeyboardInput'));
      keyboardSchedule.add(genericCameraPanSystem);
    }
    // Also add to Input schedule for drag gestures (event-driven)
    inputSchedule.add(genericCameraPanSystem);
  }
  if (enableScrollZoom) {
    inputSchedule.add(scrollZoomSystem);
  }
  if (enablePinchZoom) {
    inputSchedule.add(pinchZoomSystem);
  }
  if (enableScrollToZoomAction) {
    inputSchedule.add(scrollToZoomActionSystem);
  }
  if (enableEntityDragging) {
    inputSchedule.add(entityDraggingSystem);
  }

  // Note: Camera target systems (cameraFollowTargetSystem, etc.) and update systems
  // (cameraSmoothingSystem, cameraConstraintsSystem, etc.) should be added separately.
  // They can be added to Input schedule manually or to a separate Camera schedule.
}
