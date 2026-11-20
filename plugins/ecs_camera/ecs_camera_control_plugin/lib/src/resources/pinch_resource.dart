import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

/// Resource that tracks previous pinch scale for each camera to calculate deltas.
class PinchZoomResource extends Resource {
  /// Maps camera entity to previous pinch scale for delta calculation
  final Map<Entity, double> _previousScales = {};

  /// Maps camera entity to initial world focal point for gesture
  final Map<Entity, ui.Offset> _worldFocalPoints = {};

  PinchZoomResource();

  /// Clear state (useful for testing or reset)
  void clear() {
    _previousScales.clear();
    _worldFocalPoints.clear();
  }

  /// Get previous scale for a camera, defaulting to 1.0
  double getPreviousScale(Entity cameraEntity) =>
      _previousScales[cameraEntity] ?? 1.0;

  /// Update previous scale for a camera
  void setPreviousScale(Entity cameraEntity, double scale) {
    _previousScales[cameraEntity] = scale;
  }

  /// Get world focal point for a camera (null if not set)
  ui.Offset? getWorldFocalPoint(Entity cameraEntity) =>
      _worldFocalPoints[cameraEntity];

  /// Set world focal point for a camera
  void setWorldFocalPoint(
    Entity cameraEntity,
    ui.Offset focalPoint,
  ) {
    _worldFocalPoints[cameraEntity] = focalPoint;
  }

  /// Clear world focal point for a camera
  void clearWorldFocalPoint(Entity cameraEntity) {
    _worldFocalPoints.remove(cameraEntity);
  }
}
