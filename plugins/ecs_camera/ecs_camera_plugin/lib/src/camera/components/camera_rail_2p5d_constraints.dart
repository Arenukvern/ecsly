import 'package:ecsly/ecsly.dart';

/// Deterministic 2.5D rail clamps for cinematic valley-style cameras.
class CameraRail2p5DConstraints extends Component {
  /// Creates deterministic rail constraints for 2.5D camera motion.
  const CameraRail2p5DConstraints({
    required this.minX,
    required this.maxX,
    required this.fixedY,
    required this.fixedZ,
    required this.minYawDeg,
    required this.maxYawDeg,
    required this.fixedPitchDeg,
    required this.minFov,
    required this.maxFov,
  });

  /// Minimum rail X coordinate.
  final double minX;

  /// Maximum rail X coordinate.
  final double maxX;

  /// Fixed Y coordinate.
  final double fixedY;

  /// Fixed Z coordinate.
  final double fixedZ;

  /// Minimum yaw in degrees.
  final double minYawDeg;

  /// Maximum yaw in degrees.
  final double maxYawDeg;

  /// Fixed pitch in degrees.
  final double fixedPitchDeg;

  /// Minimum perspective FOV/zoom value.
  final double minFov;

  /// Maximum perspective FOV/zoom value.
  final double maxFov;
}
