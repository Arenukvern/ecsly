import 'package:ecsly/ecsly.dart';

/// Result of the most recent picking query.
///
/// Written by a picking backend (physics, mesh, GPU, etc.) when
/// [PickingIntentResource.pending] is drained. Consumers should
/// check [hasNewHit] and clear it after processing.
class PickingResultResource extends Resource {
  /// True when a backend produced a new hit this frame.
  bool hasNewHit = false;

  /// Key identifying the hit object (backend-specific semantics).
  String? hitKey;

  /// Hit position in world space.
  double hitX = 0;
  double hitY = 0;
  double hitZ = 0;

  /// Hit normal in world space.
  double normalX = 0;
  double normalY = 0;
  double normalZ = 0;

  /// Distance from ray origin to hit point.
  double distance = 0;
}
