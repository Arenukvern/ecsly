import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';

/// Syncs [CameraInteractionModeResource] and active camera zoom into
/// [InputWorldSpaceResource] so input systems can run without camera imports.
void inputWorldSpaceSyncSystem(final World world) {
  final mode = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;
  if (mode == null) return;

  if (!world.resources.has<InputWorldSpaceResource>()) {
    world.upsertResource(InputWorldSpaceResource());
  }
  final inputWorld = world.getResource<InputWorldSpaceResource>();

  inputWorld.allowsEntitySelection = mode.allowsEntitySelection;

  double? zoom;
  try {
    for (final (entity, pos)
        in world.queryExt<CameraPositionComponent, CameraPosition>()) {
      final (ext, valid) = world.getEntity(entity.entity);
      if (!valid) continue;
      final camera = ext.get<CameraComponent>();
      if (camera != null && camera.isActive) {
        zoom = pos.zoom;
        break;
      }
    }
  } catch (_) {}
  if (zoom != null) {
    inputWorld.zoom = zoom;
  }
}
