import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

/// Tracks the current viewport/canvas size and offset for coordinate calculations.
///
/// Updated by UnifiedInputWidget or other rendering widgets.
/// Used by camera systems for coordinate conversion and zoom-to-fit calculations.
///
/// The canvasOffset tracks how much the canvas is offset from the screen origin.
/// This is primarily used for legacy coordinate conversion. For proper camera-aware
/// coordinate conversion, use `createCameraToWorldConverter` from camera plugin.
class ViewportSizeResource extends Resource {
  /// Creates a viewport snapshot resource.
  ViewportSizeResource({
    this.width = 800.0,
    this.height = 600.0,
    this.canvasOffset = ui.Offset.zero,
  });

  /// Viewport width in logical pixels.
  double width;

  /// Viewport height in logical pixels.
  double height;

  /// Canvas offset relative to screen origin.
  ui.Offset canvasOffset;

  /// Width/height ratio.
  double get aspectRatio => width / height;

  /// Viewport bounds from origin.
  ui.Rect get bounds => ui.Rect.fromLTWH(0, 0, width, height);

  /// Viewport size as `ui.Size`.
  ui.Size get size => ui.Size(width, height);

  /// Updates width/height from a new size.
  void update(final ui.Size size) {
    width = size.width;
    height = size.height;
  }
}
