import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

/// Enables dragging selected entities.
class CameraDragAction extends Component {
  const CameraDragAction({this.trigger, this.requiresSelection = true});

  final InputAction? trigger;
  final bool requiresSelection;
}

/// Enables camera panning via input actions.
class CameraPanAction extends Component {
  const CameraPanAction({
    this.trigger,
    this.speed = 1.0,
    this.mode = PanMode.world,
  });

  /// Input action that triggers panning (null = always active)
  final InputAction? trigger;

  /// Pan speed multiplier
  final double speed;

  /// Pan mode
  final PanMode mode;
}

/// Enables entity selection via camera.
class CameraSelectAction extends Component {
  const CameraSelectAction({
    this.singleSelect,
    this.multiSelect,
    this.boxSelect,
  });

  final InputAction? singleSelect;
  final InputAction? multiSelect; // Shift+Click
  final InputAction? boxSelect; // Drag to select area
}

/// Enables camera zooming via input actions.
/// Zoom limits are controlled by CameraConstraints component.
class CameraZoomAction extends Component {
  const CameraZoomAction({
    this.trigger,
    this.speed = 1.0,
    this.mode = ZoomMode.exponential,
  });

  final InputAction? trigger;
  final double speed;
  final ZoomMode mode;
}

enum PanMode {
  /// Pan in world coordinates (affected by zoom)
  world,

  /// Pan in screen coordinates (unaffected by zoom)
  screen,

  /// Pan by modifying camera velocity
  velocity,
}

enum ZoomMode { linear, exponential }
