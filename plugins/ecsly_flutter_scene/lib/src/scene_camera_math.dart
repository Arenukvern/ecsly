// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

/// Camera math shared by the view's two pointer-facing reads — VOSGES
/// picking (which named visual is under the pointer) and consumer label
/// overlays (where does a world position land on screen). Pure vector
/// math over the SAME camera convention the view renders with: a
/// perspective camera (default vertical FOV 45°, flutter_scene's
/// [PerspectiveCamera] default) looking from [SceneCameraRig]-shaped
/// eye/target pairs. No Flutter, no renderer — everything here is
/// unit-testable headless.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'visual_state.dart';

/// flutter_scene's default vertical FOV, in radians (45°) — the view
/// creates its [PerspectiveCamera] without overriding it, so picking and
/// projection MUST use the same constant.
const double defaultFovRadiansY = 45 * math.pi / 180;

/// The derived camera basis for one eye/target pair: forward/right/up
/// axes and the vertical half-FOV tangent. World-up is (0,1,0); pitch is
/// clamped by the rig away from the degenerate straight-down case.
class SceneCameraBasis {
  /// Builds the basis. [aspect] is width/height of the viewport the
  /// pointer (or label) coordinates refer to.
  factory SceneCameraBasis({
    required List<double> eye,
    required List<double> target,
    required double aspect,
    double fovRadiansY = defaultFovRadiansY,
  }) {
    final e = vm.Vector3(eye[0], eye[1], eye[2]);
    final t = vm.Vector3(target[0], target[1], target[2]);
    final forward = (t - e)..normalize();
    var right = forward.cross(vm.Vector3(0, 1, 0));
    if (right.length2 < 1e-8) {
      // Straight down/up (never reached through the rig's pitch clamp,
      // but a basis must exist for any input): fall back to +X.
      right = forward.cross(vm.Vector3(0, 0, 1));
    }
    right.normalize();
    final up = right.cross(forward)..normalize();
    return SceneCameraBasis._(
      e,
      forward,
      right,
      up,
      math.tan(fovRadiansY / 2),
      aspect,
    );
  }

  SceneCameraBasis._(
    this.eye,
    this.forward,
    this.right,
    this.up,
    this.tanHalfFovY,
    this.aspect,
  );

  /// The camera eye in world units.
  final vm.Vector3 eye;

  /// Unit axis from the eye toward the target.
  final vm.Vector3 forward;

  /// Unit axis perpendicular to [forward] and world-up.
  final vm.Vector3 right;

  /// Unit axis perpendicular to [right] and [forward].
  final vm.Vector3 up;

  /// tan(fovY / 2) — the vertical half-FOV tangent.
  final double tanHalfFovY;

  /// Viewport width / height the caller's coordinates refer to.
  final double aspect;

  /// The ray through NDC coordinates (x,y in [-1,1], y up) of a viewport
  /// with this basis: origin = eye.
  vm.Ray rayThrough(double ndcX, double ndcY) {
    final dir =
        forward +
        right * (ndcX * tanHalfFovY * aspect) +
        up * (ndcY * tanHalfFovY);
    dir.normalize();
    return vm.Ray.originDirection(eye, dir);
  }

  /// Pointer pixel → NDC. [height] > 0.
  (double, double) ndcOfPointer(
    double px,
    double py,
    double width,
    double height,
  ) => (2 * px / width - 1, 1 - 2 * py / height);

  /// World position → NDC (y up), or null when behind the camera.
  (double, double)? ndcOfWorld(vm.Vector3 position) {
    final v = position - eye;
    final z = v.dot(forward);
    if (z <= 0) return null;
    return (
      v.dot(right) / (z * tanHalfFovY * aspect),
      v.dot(up) / (z * tanHalfFovY),
    );
  }

  /// The XYZ-list flavor of [ndcOfWorld] — the mapping wire form.
  (double, double)? ndcOfPoint(List<double> position) => ndcOfWorld(
    vm.Vector3(
      position[0],
      position.length > 1 ? position[1] : 0,
      position.length > 2 ? position[2] : 0,
    ),
  );
}

/// Distance along [ray] to the closest intersection with the sphere at
/// [center] with [radius], or null when the ray misses it.
double? raySphere(vm.Ray ray, vm.Vector3 center, double radius) {
  final oc = ray.origin - center;
  final b = oc.dot(ray.direction);
  final c = oc.dot(oc) - radius * radius;
  final disc = b * b - c;
  if (disc < 0) return null;
  final sq = math.sqrt(disc);
  final t0 = -b - sq;
  if (t0 > 0) return t0;
  final t1 = -b + sq;
  return t1 > 0 ? t1 : null;
}

/// One pick hit: the visual's key, its [pickId], and the ray distance
/// (smaller = nearer the camera).
final class ScenePickHit {
  /// Creates a pick hit.
  const ScenePickHit(this.key, this.pickId, this.distance);

  /// The visual's stable mapping key.
  final String key;

  /// The id the view's pick gestures report back.
  final String pickId;

  /// Ray distance to the hit (smaller = nearer the camera).
  final double distance;
}

/// Picks the nearest visual with a [VisualState.pickId] whose sphere
/// (center = position, radius = size) the ray hits. Pick targets are
/// spheres by law — the grammar's tap/hold targets are actors — so a
/// cuboid step never intercepts an actor's gesture.
ScenePickHit? pickVisuals({
  required Map<String, VisualState> visuals,
  required vm.Ray ray,
}) {
  ScenePickHit? best;
  for (final entry in visuals.entries) {
    final visual = entry.value;
    final pickId = visual.pickId;
    if (pickId == null || visual.shape != SceneShape.sphere) continue;
    final center = vm.Vector3(
      visual.position[0],
      visual.position.length > 1 ? visual.position[1] : 0,
      visual.position.length > 2 ? visual.position[2] : 0,
    );
    final t = raySphere(ray, center, visual.size);
    if (t == null) continue;
    if (best == null || t < best.distance) {
      best = ScenePickHit(entry.key, pickId, t);
    }
  }
  return best;
}
