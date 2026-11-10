import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import 'camera_control_schedule.dart';
import 'components/camera_action_components.dart';
import 'resources/camera_interaction_mode_resource.dart';

/// Plugin that wires InputPlugin and CameraPlugin together for camera control.
///
/// This plugin provides input-based camera control (pan, zoom, scroll).
/// It requires both InputPlugin and CameraPlugin to be installed.
///
/// **Features:**
/// - Camera panning via keyboard (WASD) or drag gestures
/// - Camera zooming via keyboard or scroll wheel
/// - Camera presets with input bindings
/// - Entity dragging with zoom-aware movement scaling
/// - Action components: CameraPanAction, CameraZoomAction, etc.
class CameraControlPlugin extends Plugin {
  /// Whether to configure camera control systems in Input schedule
  final bool configureSchedule;

  /// Whether to enable camera panning via input
  final bool enablePan;

  /// Whether to enable camera zooming via input
  final bool enableZoom;

  /// Whether to enable scroll-to-zoom
  final bool enableScrollZoom;

  /// Whether to enable pinch-to-zoom
  final bool enablePinchZoom;

  /// Whether to enable scroll-to-zoom via InputActionEvent
  ///
  /// Note: scrollZoomSystem provides direct scroll handling and is enabled by default.
  /// This action-based system is for advanced use cases requiring action pipeline integration.
  final bool enableScrollToZoomAction;

  /// Whether to enable entity dragging (requires InputPlugin)
  final bool enableEntityDragging;

  /// Creates a CameraControlPlugin.
  ///
  /// [configureSchedule] - Whether to configure camera control systems in Input schedule
  /// [enablePan] - Whether to enable camera panning via input
  /// [enableZoom] - Whether to enable camera zooming via input
  /// [enableScrollZoom] - Whether to enable scroll-to-zoom
  /// [enablePinchZoom] - Whether to enable pinch-to-zoom
  /// [enableScrollToZoomAction] - Whether to enable scroll-to-zoom via InputActionEvent
  /// [enableEntityDragging] - Whether to enable entity dragging (requires InputPlugin)
  const CameraControlPlugin({
    this.configureSchedule = true,
    this.enablePan = true,
    this.enableZoom = true,
    this.enableScrollZoom = true,
    this.enablePinchZoom = true,
    this.enableScrollToZoomAction = false,
    this.enableEntityDragging = false,
  });

  @override
  String get name => 'CameraControl';

  @override
  void install(final World world) {
    // Verify dependencies
    if (!world.hasPlugin('Input')) {
      throw StateError(
        'InputPlugin must be installed before CameraControlPlugin. '
        'Add InputPlugin to your world first.',
      );
    }
    if (!world.hasPlugin('Camera')) {
      throw StateError(
        'CameraPlugin must be installed before CameraControlPlugin. '
        'Add CameraPlugin to your world first.',
      );
    }

    // Register action components
    world.components.registerObjectComponent<CameraPanAction>();
    world.components.registerObjectComponent<CameraZoomAction>();
    world.components.registerObjectComponent<CameraSelectAction>();
    world.components.registerObjectComponent<CameraDragAction>();

    // Register camera interaction mode resource
    final mode = CameraInteractionModeResource();
    world.upsertResource(mode);
    // So input systems can read without camera imports
    world.upsertResource(
      InputWorldSpaceResource(
        allowsEntitySelection: mode.allowsEntitySelection,
        zoom: 1.0,
      ),
    );

    // Configure schedule if requested
    if (configureSchedule) {
      configureCameraControlSchedule(
        world,
        enablePan: enablePan,
        enableZoom: enableZoom,
        enableScrollZoom: enableScrollZoom,
        enablePinchZoom: enablePinchZoom,
        enableScrollToZoomAction: enableScrollToZoomAction,
        enableEntityDragging: enableEntityDragging,
      );
    }
  }
}
