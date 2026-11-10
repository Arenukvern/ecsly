import 'package:ecsly/ecsly.dart';

/// Marker component identifying an entity as a camera.
///
/// Cameras can be queried to find active cameras or cameras with specific
/// behaviors. Multiple cameras are supported for split-screen, minimaps, etc.
class CameraComponent extends Component {
  /// Creates a camera marker with activation and culling settings.
  CameraComponent({
    this.isActive = true,
    this.priority = 0,
    this.cullingPadding = 100.0,
  });

  /// Whether this camera is currently active.
  /// Only active cameras are used for rendering.
  bool isActive;

  /// Priority for rendering order (higher priority cameras render first).
  /// Useful for layering multiple cameras (e.g., minimap over main camera).
  int priority;

  /// Padding added to view bounds for entity culling (in world units).
  /// Larger values include more entities outside the viewport for smoother rendering.
  /// Default: 100.0
  final double cullingPadding;
}
