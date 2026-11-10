import 'package:ecsly/ecsly.dart';

/// Simplified interaction mode with clear semantics for camera control.
enum CameraInteractionMode {
  /// WASD/player control, entities selectable, camera follows
  game,

  /// Pan/zoom camera, drag entities, no player control
  editor,

  /// No input, scripted camera movement
  cinematic,
}

/// Resource that manages the current camera interaction mode and related configuration.
///
/// This resource provides camera-specific interaction modes and capabilities.
/// Input systems can check for its existence optionally to enable camera-aware behavior.
/// When this resource is not present, input systems use default behavior (all interactions allowed).
///
/// Clear semantics: game, editor, cinematic.
/// No conflicting boolean flags - capabilities computed from mode.
class CameraInteractionModeResource extends Resource {
  CameraInteractionModeResource({
    this.mode = CameraInteractionMode.game,
    this.panSpeed = 1.0,
    this.zoomSpeed = 1.0,
    this.minZoom = 0.1,
    this.maxZoom = 5.0,
    this.scrollZoomSpeed = 0.1,
  });

  /// Current interaction mode
  CameraInteractionMode mode;

  /// Configuration (not mode-dependent)
  double panSpeed;
  double zoomSpeed;
  double scrollZoomSpeed;
  double minZoom;
  double maxZoom;

  /// Capabilities derived from mode
  bool get allowsCameraPan => mode == CameraInteractionMode.editor;
  bool get allowsCameraZoom => mode != CameraInteractionMode.cinematic;
  bool get allowsEntityDragging => mode == CameraInteractionMode.editor;
  bool get allowsEntitySelection => mode != CameraInteractionMode.cinematic;
}
