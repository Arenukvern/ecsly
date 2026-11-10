import 'dart:ui' as ui;

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
/// instead. Mapping (the city-builder standard — CS/Train Fever/TheoTown —
/// matching the flutter_scene adapter's gestures):
///
/// - left-drag / one-finger touch → PAN the orbit target (grab-the-world)
/// - middle-button drag OR shift-drag → ORBIT (yaw + pitch)
/// - two-finger drag → PAN + PINCH dolly + TWIST yaw (cumulative scale /
///   rotation are converted to per-update deltas via the resource's
///   `lastPinchScale` / `lastPinchRotation`, reset on RawScaleStart/End)
/// - scroll wheel → dolly zoom; double-tap → zoom-in step. With
///   [OrbitCameraResource.zoomAtCursor] both keep the ground point under the
///   cursor fixed (the bridge projects it into the events' `worldPosition`
///   as Offset(worldX, worldZ)).
///
/// Coordination with other consumers (editor paint drags, entity dragging):
/// events marked in [GestureConsumptionTracker] are skipped, and while a
/// transform gesture (multi-touch or pinch/twist) owns the frame the
/// per-pointer [DragEvent]s are ignored so panning is not applied twice.
///
/// Mode gating: when a [CameraInteractionModeResource] is present, manual
/// camera navigation is suppressed in `cinematic` (scripted) mode and allowed
/// otherwise. Absent the resource, everything is allowed (standalone use).
///
/// Runs in the Input schedule via [configureOrbitCameraControlSchedule];
/// keyboard navigation is the sibling [orbitCameraKeyboardSystem].
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

  final tracker = world.resources.has<GestureConsumptionTracker>()
      ? world.getResource<GestureConsumptionTracker>()
      : null;

  // Gesture-boundary resets for the cumulative pinch deltas.
  for (final _ in world.events.reader<RawScaleStartEvent>().iter()) {
    cam.resetPinchGesture();
  }

  // Does a transform gesture (touch transform / trackpad pinch) own this
  // frame? Then the per-pointer DragEvents of the same gesture must not pan
  // a second time — the PinchEvent pass below owns the movement.
  var transformActive = false;
  for (final pinch in world.events.reader<PinchEvent>().iter()) {
    if (tracker != null && tracker.isPinchConsumed(pinch)) continue;
    if (pinch.pointerCount >= 2 || pinch.scale != 1 || pinch.rotation != 0) {
      transformActive = true;
      break;
    }
  }

  // Drag: middle-button or shift orbits, everything else pans.
  if (!transformActive) {
    for (final drag in world.events.reader<DragEvent>().iter()) {
      if (tracker != null && tracker.isDragConsumed(drag)) continue;
      final orbits =
          (drag.buttons & kOrbitMiddleButton) != 0 ||
          (drag.modifierMask & inputModifierShiftMask) != 0;
      if (orbits) {
        cam.orbit(drag.delta.dx, drag.delta.dy);
      } else {
        cam.pan(drag.delta.dx, drag.delta.dy);
      }
    }
  }

  for (final _ in world.events.reader<RawScaleEndEvent>().iter()) {
    cam.resetPinchGesture();
  }

  // Pinch / trackpad pan-zoom: focal pan + pinch dolly + twist yaw.
  for (final pinch in world.events.reader<PinchEvent>().iter()) {
    if (tracker != null && tracker.isPinchConsumed(pinch)) continue;
    final isTransform =
        pinch.pointerCount >= 2 || pinch.scale != 1 || pinch.rotation != 0;
    // pointerCount 0 with a pure pan delta = host-converted trackpad scroll
    // (UnifiedInputWidget trackpadScrollCausesPan). A single pointer with
    // scale == 1 and no rotation is an ordinary mouse/touch drag — already
    // handled by the DragEvent pass.
    final isTrackpadPan =
        pinch.pointerCount == 0 &&
        pinch.scale == 1 &&
        pinch.rotation == 0 &&
        pinch.focalPointDelta != ui.Offset.zero;
    if (!isTransform && !isTrackpadPan) continue;

    if (pinch.focalPointDelta != ui.Offset.zero) {
      cam.pan(pinch.focalPointDelta.dx, pinch.focalPointDelta.dy);
    }
    final ratio = cam.lastPinchScale == 0
        ? 1
        : pinch.scale / cam.lastPinchScale;
    cam.lastPinchScale = pinch.scale;
    if (ratio != 1) {
      if (cam.zoomAtCursor) {
        cam.zoomAt(
          1 / ratio,
          pinch.worldPosition.dx,
          cam.targetY,
          pinch.worldPosition.dy,
        );
      } else {
        cam.zoom(1 / ratio);
      }
    }
    final twist = pinch.rotation - cam.lastPinchRotation;
    cam.lastPinchRotation = pinch.rotation;
    cam.yaw += twist;
  }

  // Scroll wheel: dolly. Scroll up (negative dy) zooms in, matching the
  // adapter and the 2D scrollZoomSystem.
  for (final scroll in world.events.reader<ScrollEvent>().iter()) {
    if (tracker != null && tracker.isScrollConsumed(scroll)) continue;
    final factor = scroll.delta.dy > 0 ? 1.1 : 0.9;
    if (cam.zoomAtCursor) {
      cam.zoomAt(
        factor,
        scroll.worldPosition.dx,
        cam.targetY,
        scroll.worldPosition.dy,
      );
    } else {
      cam.zoom(factor);
    }
  }

  // Double-tap: one zoom-in step (at the cursor when projected).
  for (final tap in world.events.reader<DoubleTapEvent>().iter()) {
    if (tracker != null && tracker.isDoubleTapConsumed(tap)) continue;
    if (cam.zoomAtCursor) {
      cam.zoomAt(0.8, tap.worldPosition.dx, cam.targetY, tap.worldPosition.dy);
    } else {
      cam.zoom(0.8);
    }
  }
}

/// Adds [orbitCameraControlSystem] to the Input schedule (event-driven, so it
/// runs only on frames with input). Requires InputPlugin's `Input` schedule.
///
/// Ordering is EXPLICIT: the ecsly scheduler resolves unconstrained systems
/// alphabetically, not by insertion order, so the system is pinned after
/// gesture classification and before the end-of-run event clear. Hosts adding
/// their own Input-schedule systems (editor drags that consume events, for
/// instance) must chain them the same way — see `configureInputSchedule`.
void configureOrbitCameraControlSchedule(final World world) {
  if (!world.hasSchedule(const ScheduleId('Input'))) {
    throw StateError(
      'Input schedule not found. Install InputPlugin (with configureSchedule) '
      'before configureOrbitCameraControlSchedule.',
    );
  }
  world
      .schedule(const ScheduleId('Input'))
      .add(
        orbitCameraControlSystem,
        name: 'orbitCameraControlSystem',
        runAfter: ['scaleClassificationSystem'],
        runBefore: ['eventInputClearSystem'],
      );
}
