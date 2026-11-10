import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';
import '../resources/orbit_camera_resource.dart';

/// Mouse-button bitmasks, matching dart:ui / Flutter pointer buttons
/// (kPrimaryButton=0x01, kSecondaryButton=0x02, kTertiaryButton=0x04). A
/// [DragEvent] carries these in `buttons`, so the orbit/pan split survives the
/// trip from Flutter into renderer-agnostic ECS events.
const int kOrbitPrimaryButton = 0x01;

/// Secondary (right) mouse button bitmask.
const int kOrbitSecondaryButton = 0x02;

/// Middle (tertiary) mouse button bitmask — the orbit modifier.
const int kOrbitMiddleButton = 0x04;

/// Drives an [OrbitCameraResource] from ECS input events — the
/// renderer-agnostic half of "flutter_scene only bridges it". This is the 3D
/// counterpart to [genericCameraPanSystem]/[scrollZoomSystem], which mutate a
/// 2D top-down `CameraPosition`; a 3D orbit host (yaw/pitch/distance) uses this
/// instead. Mapping (the city-builder standard, matching the flutter_scene
/// adapter's gestures):
///
/// - left-drag / one-finger touch → PAN the orbit target
/// - middle-button drag → ORBIT (yaw + pitch)
/// - scroll wheel → dolly zoom (toward the target; zoom-at-cursor is a bridge
///   concern — see [OrbitCameraResource.zoomAt])
///
/// Mode gating: when a [CameraInteractionModeResource] is present, manual
/// camera navigation is suppressed in `cinematic` (scripted) mode and allowed
/// otherwise. Absent the resource, everything is allowed (standalone use).
///
/// Hosts can extend this (keyboard pan/orbit, two-finger twist) or run it
/// per-frame in the Input schedule via [configureOrbitCameraControlSchedule].
void orbitCameraControlSystem(final World world) {
  if (!world.resources.has<OrbitCameraResource>()) return;
  final cam = world.getResource<OrbitCameraResource>();

  // Cinematic mode = scripted camera; ignore manual input. (The 2D systems'
  // editor-only pan gate doesn't fit a city-builder god-view, so orbit nav is
  // allowed in any non-cinematic mode.)
  if (world.resources.has<CameraInteractionModeResource>()) {
    final mode = world.getResource<CameraInteractionModeResource>();
    if (mode.mode == CameraInteractionMode.cinematic) return;
  }

  // Drag: middle-button orbits, everything else pans (grab-the-world).
  for (final drag in world.events.reader<DragEvent>().iter()) {
    if ((drag.buttons & kOrbitMiddleButton) != 0) {
      cam.orbit(drag.delta.dx, drag.delta.dy);
    } else {
      cam.pan(drag.delta.dx, drag.delta.dy);
    }
  }

  // Scroll wheel: dolly. Scroll up (negative dy) zooms in, matching the
  // adapter and the 2D scrollZoomSystem.
  for (final scroll in world.events.reader<ScrollEvent>().iter()) {
    cam.zoom(scroll.delta.dy > 0 ? 1.1 : 0.9);
  }
}

/// Adds [orbitCameraControlSystem] to the Input schedule (event-driven, so it
/// runs only on frames with input). Requires InputPlugin's `Input` schedule.
void configureOrbitCameraControlSchedule(final World world) {
  if (!world.hasSchedule(const ScheduleId('Input'))) {
    throw StateError(
      'Input schedule not found. Install InputPlugin (with configureSchedule) '
      'before configureOrbitCameraControlSchedule.',
    );
  }
  world
      .schedule(const ScheduleId('Input'))
      .add(orbitCameraControlSystem, name: 'orbitCameraControlSystem');
}
