import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Renderer-agnostic 3D orbit-camera state + math.
///
/// A spherical orbit camera: [yaw]/[pitch] (radians) orbit a [targetX]/
/// [targetY]/[targetZ] point at [distance]. This is the ECS-native equivalent
/// of a renderer's orbit rig — control systems mutate it from input events,
/// and a renderer bridge (e.g. flutter_scene) reads [cameraPosition] /
/// [cameraTarget] each frame to place the actual camera. Keeping the state in
/// a [Resource] is what makes "controls independent of the renderer, renderer
/// only bridges it" possible: the same orbit state can drive flutter_scene,
/// a 2D canvas, a headless capture, or a replay.
///
/// Sign convention matches flutter_scene's LEFT-HANDED render (grab-the-world):
/// drag right → [yaw] increases, drag down → [pitch] lowers, and [pan] moves
/// the target so content follows the pointer. Derivation: see the car_vs_walk_game
/// `docs/CAMERA_AND_PICKING.md` and the adapter's `SceneCameraRig` (the two must
/// agree; the adapter convention test pins the handedness).
class OrbitCameraResource extends Resource {
  /// Creates an orbit camera. Defaults match the game's rig (yaw 0.6, pitch
  /// 0.5) so a host can drop it in without a visual jump.
  OrbitCameraResource({
    this.yaw = 0.6,
    this.pitch = 0.5,
    this.distance = 24,
    this.targetX = 0,
    this.targetY = 0,
    this.targetZ = 0,
    this.minPitch = -1.45,
    this.maxPitch = 1.45,
    this.minDistance = 0.5,
    this.maxDistance = 400,
    this.orbitSensitivity = 0.01,
    this.panScale = 0.0016,
  });

  /// Orbit angle around the target's Y axis (radians).
  double yaw;

  /// Elevation angle above the target's horizon (radians), clamped.
  double pitch;

  /// Distance from the target to the eye (world units), clamped.
  double distance;

  /// Orbit target (the point the camera looks at), world X.
  double targetX;

  /// Orbit target, world Y (height).
  double targetY;

  /// Orbit target, world Z.
  double targetZ;

  /// Lower pitch clamp (radians) — keeps the eye off the straight-down singularity.
  final double minPitch;

  /// Upper pitch clamp (radians).
  final double maxPitch;

  /// Minimum zoom distance.
  final double minDistance;

  /// Maximum zoom distance.
  final double maxDistance;

  /// Radians of yaw/pitch per pixel of drag.
  final double orbitSensitivity;

  /// Pan distance factor (rides [distance] so panning feels constant per zoom).
  final double panScale;

  /// Grab-the-world orbit: [dx] spins yaw, [dy] tilts pitch (clamped).
  void orbit(final double dx, final double dy) {
    yaw += dx * orbitSensitivity;
    pitch = math.max(
      minPitch,
      math.min(maxPitch, pitch - dy * orbitSensitivity),
    );
  }

  /// Grab-the-world pan: slide the target across the ground plane (XZ),
  /// camera-relative, scaled by [distance]. Sign-derived from flutter_scene's
  /// left-handed screen axes (see class doc).
  void pan(final double dx, final double dy) {
    final s = distance * panScale;
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    targetX += (dx * cosYaw - dy * sinYaw) * s;
    targetZ += (-dx * sinYaw - dy * cosYaw) * s;
  }

  /// Scales [distance] by [factor] (clamped). factor < 1 zooms in.
  void zoom(final double factor) {
    distance = math.max(
      minDistance,
      math.min(maxDistance, distance * factor),
    );
  }

  /// Zoom-at-cursor: scale [distance] by [factor] while sliding the target
  /// toward the world point ([wx], [wy], [wz]) so that point stays fixed on
  /// screen. The renderer bridge computes the world point (it owns the
  /// projection); this stays renderer-agnostic. factor < 1 zooms in.
  void zoomAt(
    final double factor,
    final double wx,
    final double wy,
    final double wz,
  ) {
    final before = distance;
    zoom(factor);
    if (before <= 0) return;
    final keep = 1 - distance / before;
    targetX += (wx - targetX) * keep;
    targetY += (wy - targetY) * keep;
    targetZ += (wz - targetZ) * keep;
  }

  /// Points the camera at a world position (agent close-up / focus actions).
  void focus(final double x, final double y, final double z) {
    targetX = x;
    targetY = y;
    targetZ = z;
  }

  /// The camera eye in world space for the current orbit state.
  vm.Vector3 cameraPosition() {
    final cosPitch = math.cos(pitch);
    return vm.Vector3(
      targetX + distance * cosPitch * math.sin(yaw),
      targetY + distance * math.sin(pitch),
      targetZ + distance * cosPitch * math.cos(yaw),
    );
  }

  /// The orbit target in world space.
  vm.Vector3 cameraTarget() => vm.Vector3(targetX, targetY, targetZ);
}
