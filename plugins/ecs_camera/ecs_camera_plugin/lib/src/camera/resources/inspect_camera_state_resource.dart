import 'package:ecsly/ecsly.dart';

/// Shared inspect camera state and limits for hosts that prefer a resource.
class InspectCameraStateResource extends Resource {
  /// Creates inspect-camera orbit state and safety limits.
  InspectCameraStateResource({
    this.targetX = 0.0,
    this.targetY = 0.0,
    this.targetZ = 0.0,
    this.yawDeg = 0.0,
    this.pitchDeg = 0.0,
    this.distance = 12.0,
    this.minPitchDeg = -89.0,
    this.maxPitchDeg = 89.0,
    this.minDistance = 0.1,
    this.maxDistance = 1000.0,
  });

  /// Orbit target X coordinate.
  double targetX;

  /// Orbit target Y coordinate.
  double targetY;

  /// Orbit target Z coordinate.
  double targetZ;

  /// Orbit yaw in degrees.
  double yawDeg;

  /// Orbit pitch in degrees.
  double pitchDeg;

  /// Orbit distance from target.
  double distance;

  /// Minimum allowed pitch in degrees.
  double minPitchDeg;

  /// Maximum allowed pitch in degrees.
  double maxPitchDeg;

  /// Minimum allowed distance.
  double minDistance;

  /// Maximum allowed distance.
  double maxDistance;
}
