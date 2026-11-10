import 'package:ecsly/ecsly.dart';

import 'camera_constraints.dart';

/// Automatically zooms camera to fit target entities.
///
/// This component enables automatic zoom adjustment to ensure all target
/// entities are visible within the viewport. The cameraZoomToFitSystem
/// processes this component and adjusts camera zoom accordingly.
///
/// Zoom bounds specified here are hints - actual zoom clamping is handled
/// by the [CameraConstraints] component for consistent global camera limits.
class CameraZoomToFit extends Component {
  /// Creates auto-fit settings for keeping target entities on screen.
  const CameraZoomToFit({
    required this.targets,
    this.padding = 50.0,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.maintainAspectRatio = true,
  });

  /// List of entities to fit in viewport
  final List<Entity> targets;

  /// Padding around entities in pixels
  final double padding;

  /// Minimum zoom level
  final double minZoom;

  /// Maximum zoom level
  final double maxZoom;

  /// Whether to maintain aspect ratio when fitting
  final bool maintainAspectRatio;
}
