import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';
import '../resources/orbit_camera_resource.dart';

/// Drives an [OrbitCameraResource] from KEYBOARD input actions — the
/// remappable half of the orbit control. Bindings live in [RuntimeInputMap]
/// data (the InputPlugin defaults: WASD/arrows → move*, +/- → zoom,
/// R → cameraReset); this system only reads the resulting held/pressed
/// actions from [InputStateTracker], so rebinding is pure data.
///
/// Mapping (grab-the-world parity with the pointer control):
/// - moveLeft/moveRight/moveUp/moveDown → pan the view in that screen
///   direction (a keyboard "move right" is the INVERSE of dragging right:
///   dragging grabs the world, keys move the eye)
/// - zoomIn/zoomOut → dolly, exponentially per second ([OrbitCameraResource
///   .keyZoomSpeed] halvings/doublings per second)
/// - cameraReset (justPressed) → [OrbitCameraResource.resetToHome]
///
/// Runs every frame in the KeyboardInput schedule (held keys must pan
/// continuously, and the Input schedule is event-driven). The same cinematic
/// gating as [orbitCameraControlSystem] applies. dt comes from the core
/// [DeltaTimeResource] when the host loop maintains it (the ecsly_flutter
/// fixed-step bridge does), falling back to 1/60.
void orbitCameraKeyboardSystem(final World world) {
  if (!world.resources.has<OrbitCameraResource>()) return;
  if (!world.resources.has<InputStateTracker>()) return;
  final cam = world.getResource<OrbitCameraResource>();

  if (world.resources.has<CameraInteractionModeResource>()) {
    final mode = world.getResource<CameraInteractionModeResource>();
    if (mode.mode == CameraInteractionMode.cinematic) return;
  }

  final tracker = world.getResource<InputStateTracker>();
  final dt = world.resources.has<DeltaTimeResource>()
      ? world.getResource<DeltaTimeResource>().deltaTime
      : 1 / 60;

  // Held direction axes → view-relative pan. getAxis2D gives x (right +),
  // y (up +); pan() takes grab-the-world drag deltas, so "view right" is a
  // negative dx and "view up" a positive dy.
  final (x, y) = tracker.getAxis2D(
    InputAction.moveUp,
    InputAction.moveDown,
    InputAction.moveLeft,
    InputAction.moveRight,
  );
  if (x != 0 || y != 0) {
    cam.pan(-x * cam.keyPanSpeed * dt, y * cam.keyPanSpeed * dt);
  }

  if (tracker.isHeld(InputAction.zoomIn)) {
    cam.zoom(math.pow(0.5, dt * cam.keyZoomSpeed).toDouble());
  }
  if (tracker.isHeld(InputAction.zoomOut)) {
    cam.zoom(math.pow(2.0, dt * cam.keyZoomSpeed).toDouble());
  }
  if (tracker.justPressed(InputAction.cameraReset)) {
    cam.resetToHome();
  }
}

/// Adds [orbitCameraKeyboardSystem] to the KeyboardInput schedule (every
/// frame), pinned after `inputBindingSystem` so the tracker reflects this
/// frame's keys. Ordering is explicit — the ecsly scheduler resolves
/// unconstrained systems alphabetically, not by insertion order.
void configureOrbitCameraKeyboardSchedule(final World world) {
  if (!world.hasSchedule(const ScheduleId('KeyboardInput'))) {
    throw StateError(
      'KeyboardInput schedule not found. Install InputPlugin (with '
      'configureSchedule) before configureOrbitCameraKeyboardSchedule.',
    );
  }
  world
      .schedule(const ScheduleId('KeyboardInput'))
      .add(
        orbitCameraKeyboardSystem,
        name: 'orbitCameraKeyboardSystem',
        runAfter: ['inputBindingSystem'],
      );
}
