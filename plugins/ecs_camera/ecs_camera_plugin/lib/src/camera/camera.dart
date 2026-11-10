import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

import 'components/camera_components.dart';

export 'camera_coordinate_utils.dart';
export 'camera_orientation_math.dart';
export 'camera_plugin.dart';
export 'components/camera_components.dart';
export 'systems/camera_systems.dart';

part 'camera_adapter.dart';

/// Abstract camera interface that defines viewport transformation and culling bounds.
/// Cameras handle the transformation from world coordinates to screen coordinates.
///
/// **Note:** [transformCanvas] is deprecated. All rendering should go through
/// the GPU pipeline (SceneCamera → ECS components → packet → wgpu). The Canvas
/// path will be removed once all prototypes are migrated to scene descriptions.
sealed class Camera {
  /// Gets the current zoom level.
  double get zoom;

  /// Get the world bounds currently visible on screen, used for entity culling.
  /// Returns a Rect in world coordinates representing the visible area.
  ui.Rect getViewBounds(final ui.Size viewport);

  /// Get the world position of the viewport center.
  /// Useful for camera-relative positioning of UI elements.
  ui.Offset getViewportCenter();

  /// Apply camera transformation to the canvas for rendering world coordinates.
  /// This transforms the coordinate system so that world (0,0) appears at the
  /// correct screen position based on camera settings.
  ///
  /// **Deprecated.** All rendering should use the GPU pipeline via
  /// SceneCamera → ECS camera components → UnifiedRenderPacket → wgpu.
  @Deprecated('Use SceneCamera + GPU pipeline instead of Canvas rendering.')
  void transformCanvas(final ui.Canvas canvas, final ui.Size viewport);
}
