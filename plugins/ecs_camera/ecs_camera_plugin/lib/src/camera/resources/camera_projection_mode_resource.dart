import 'package:ecsly/ecsly.dart';

/// Canonical camera projection family used by all hosts.
enum CameraProjectionMode {
  /// Orthographic projection for pure 2D scenes.
  orthographic2d,

  /// Orthographic projection with 2.5D camera semantics.
  orthographic2_5d,

  /// Perspective projection for full 3D scenes.
  perspective3d,
}

/// Frame-latched camera projection mode resource.
class CameraProjectionModeResource extends Resource {
  /// Creates the frame-latched projection mode state.
  CameraProjectionModeResource({
    this.requestedMode = CameraProjectionMode.orthographic2d,
    this.effectiveMode = CameraProjectionMode.orthographic2d,
    this.frameId = 0,
    this.latchFrameId = 0,
  });

  /// Requested projection mode from game logic.
  CameraProjectionMode requestedMode;

  /// Effective mode latched for rendering this frame.
  CameraProjectionMode effectiveMode;

  /// Current world frame id.
  int frameId;

  /// Frame id when effective mode was latched.
  int latchFrameId;
}
