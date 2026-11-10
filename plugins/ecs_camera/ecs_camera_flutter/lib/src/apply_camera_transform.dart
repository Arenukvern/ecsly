import 'dart:ui' as ui;

import 'package:ecs_camera_core/ecs_camera_core.dart';

/// Applies [camera] transform to [canvas] so world coordinates render correctly.
/// Call after [canvas.save], then draw in world space; then [canvas.restore].
///
/// **Deprecated.** All rendering should go through the GPU pipeline
/// (UnifiedRenderPacket → wgpu). Scene-description-based games use
/// [SceneCamera] which bridges into ECS camera components and renders
/// via the GPU backend. This Canvas path exists only for legacy 2D
/// painters that have not been migrated.
@Deprecated(
  'Use SceneCamera + GPU pipeline instead. '
  'Canvas rendering is removed in the scene description architecture.',
)
void applyCameraTransform(
  final ui.Canvas canvas,
  final ui.Size viewport,
  final EcsCamera2D camera,
) {
  canvas.scale(camera.zoom);
  canvas.translate(
    viewport.width / 2 - camera.centerX * camera.zoom,
    viewport.height / 2 - camera.centerY * camera.zoom,
  );
}
