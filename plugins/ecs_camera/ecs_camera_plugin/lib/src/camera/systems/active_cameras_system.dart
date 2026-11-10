import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:ecsly/ecsly.dart';

import '../components/camera_components.dart';
import '../resources/active_cameras_resource.dart';
import '../resources/camera_projection_mode_resource.dart';

/// Fills [ActiveCamerasResource] with active cameras in priority order (high first).
/// Cameras without [CameraViewportRectComponent] get [ViewportRect.fullScreen].
void activeCamerasSystem(final World world) {
  final resource = world.getResource<ActiveCamerasResource>();
  final modeResource = world.getResource<CameraProjectionModeResource>();
  resource.cameras.clear();

  final list =
      <
        ({
          Entity entity,
          int priority,
          ViewportRect viewport,
          CameraProjectionMode mode,
        })
      >[];
  for (final (we, camera) in world.query<CameraComponent>()) {
    if (!camera.isActive) continue;
    final viewportComp = we.get<CameraViewportRectComponent>();
    final viewport = viewportComp?.viewport ?? ViewportRect.fullScreen;
    list.add((
      entity: we.entity,
      priority: camera.priority,
      viewport: viewport,
      mode: modeResource.effectiveMode,
    ));
  }
  list.sort((final a, final b) => b.priority.compareTo(a.priority));
  for (final e in list) {
    resource.cameras.add(
      ActiveCameraEntry(entity: e.entity, viewport: e.viewport, mode: e.mode),
    );
  }
}
