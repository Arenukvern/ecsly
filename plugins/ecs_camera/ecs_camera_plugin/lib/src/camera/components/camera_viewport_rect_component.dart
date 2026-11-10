import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:ecsly/ecsly.dart';

/// Viewport rect for this camera (normalized 0–1). Default full screen.
/// Used for split-screen or minimap; host clips/transforms per viewport.
class CameraViewportRectComponent extends Component {
  /// Creates a viewport rect component for split-screen or minimap cameras.
  CameraViewportRectComponent({this.viewport = ViewportRect.fullScreen});

  /// Normalized viewport rectangle in 0..1 range.
  ViewportRect viewport;
}
