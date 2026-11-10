/// ECS Camera Plugin - Low-level camera system for ECS
///
/// Provides component-based camera system for 2D games.
/// Camera can be controlled programmatically via components.
/// NO input dependency.
library;

export 'package:ecs_camera_core/ecs_camera_core.dart' show ViewportRect;

export 'src/camera/camera.dart';
export 'src/camera/camera_coordinate_converter.dart';
export 'src/camera/camera_coordinate_utils.dart';
export 'src/camera/camera_orientation_math.dart';
export 'src/camera/camera_plugin.dart';
export 'src/camera/components/inspect_camera_state_component.dart';
export 'src/camera/resources/active_cameras_resource.dart';
export 'src/camera/resources/camera_projection_mode_resource.dart';
export 'src/camera/resources/inspect_camera_state_resource.dart';
export 'src/camera/resources/viewport_size_resource.dart';
export 'src/camera/systems/camera_projection_mode_latch_system.dart';
export 'src/camera/systems/camera_systems.dart';
export 'src/camera/utils/camera_utils.dart';
