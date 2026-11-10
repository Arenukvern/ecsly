/// ECS Camera Control Plugin - Camera control via input
///
/// Wires InputPlugin and CameraPlugin together to provide input-based
/// camera control (pan, zoom, scroll). Requires both InputPlugin and
/// CameraPlugin to be installed.
library;

export 'src/camera_control_plugin.dart';
export 'src/camera_control_schedule.dart';
export 'src/inspect_camera_preset.dart';
export 'src/camera_preset.dart';
export 'src/camera_preset_validator.dart';
export 'src/components/camera_action_components.dart';
export 'src/resources/camera_interaction_mode_resource.dart';
export 'src/resources/orbit_camera_resource.dart';
export 'src/systems/entity_dragging_system.dart';
export 'src/systems/generic_camera_pan_system.dart';
export 'src/systems/generic_camera_zoom_system.dart';
export 'src/systems/orbit_camera_control_system.dart';
export 'src/systems/pinch_zoom_system.dart';
export 'src/systems/scroll_to_zoom_action_system.dart';
export 'src/systems/scroll_zoom_system.dart';
