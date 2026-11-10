import 'package:ecsly/ecsly.dart';

/// Camera movement controller (composable with any target).
///
/// Controls how the camera moves when receiving input or following targets.
/// Can be combined with any CameraTarget for flexible behavior.
/// Damping is controlled by CameraVelocity component.
class CameraController extends Component {
  /// Creates an input movement controller for a camera.
  CameraController({this.moveSpeed = 200.0});

  /// Movement speed in pixels per second (for input-based movement)
  final double moveSpeed;
}

/// Camera zoom controller (composable).
///
/// Controls zoom speed for camera zoom operations.
/// Zoom limits are controlled by CameraConstraints component.
/// Can be combined with any CameraTarget for flexible behavior.
class CameraZoom extends Component {
  /// Creates an input zoom controller for a camera.
  CameraZoom({this.zoomSpeed = 1.0});

  /// Zoom speed multiplier for input-based zoom
  final double zoomSpeed;
}
