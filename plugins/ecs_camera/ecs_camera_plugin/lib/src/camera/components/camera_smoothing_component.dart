import 'package:ecsly/ecsly.dart';

/// Camera smoothing (lerp to target position/zoom).
///
/// Smoothly interpolates camera position and zoom towards their target values.
/// Uses exponential interpolation for natural movement.
/// Attach to camera entities that need smooth following behavior.
class CameraSmoothing extends Component {
  /// Creates smoothing parameters for camera position and zoom interpolation.
  CameraSmoothing({this.positionSpeed = 5.0, this.zoomSpeed = 3.0});

  /// Interpolation speed for position (higher = faster following).
  /// Uses exponential interpolation: `1.0 - exp(-speed * dt)`.
  /// Typical values: 3.0-10.0
  final double positionSpeed;

  /// Interpolation speed for zoom (higher = faster zoom changes).
  /// Uses exponential interpolation: `1.0 - exp(-speed * dt)`.
  /// Typical values: 2.0-5.0
  final double zoomSpeed;
}
