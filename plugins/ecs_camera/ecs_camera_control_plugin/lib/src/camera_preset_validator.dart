import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import 'camera_preset.dart';

/// Result of camera preset validation.
class CameraPresetValidationResult {
  /// Creates a result of camera preset validation.
  const CameraPresetValidationResult({
    required this.isValid,
    this.missingBindings = const [],
    this.errors = const [],
  });

  /// Whether the configuration is valid (no missing bindings).
  final bool isValid;

  /// List of input actions that are required but not bound.
  final List<InputAction> missingBindings;

  /// Any validation errors or warnings.
  final List<String> errors;
}

/// Validates that camera presets have corresponding input bindings configured.
///
/// Prevents runtime issues where camera preset exists but has no input bindings.
/// Common user mistake during setup - camera preset configured but input map empty.
class CameraPresetValidator {
  /// Validate that all required actions for a preset are bound.
  ///
  /// [preset] Camera preset to validate
  /// [inputMap] Input map to check for bindings
  /// Returns validation result with missing bindings if any
  CameraPresetValidationResult validatePreset(
    final CameraPreset preset,
    final RuntimeInputMap inputMap,
  ) {
    final requiredActions = _getRequiredActions(preset);
    final missingBindings = <InputAction>[];

    for (final action in requiredActions) {
      if (inputMap.getSources(action).isEmpty) {
        missingBindings.add(action);
      }
    }

    return CameraPresetValidationResult(
      isValid: missingBindings.isEmpty,
      missingBindings: missingBindings,
    );
  }

  /// Get all input actions required by a camera preset.
  ///
  /// This includes actions used by CameraPanAction, CameraZoomAction,
  /// and CameraSelectAction components created by the preset.
  List<InputAction> _getRequiredActions(
    final CameraPreset preset,
  ) => switch (preset) {
    CameraPreset.rts => [
      InputAction.cameraPan, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.attack, // For single select
      // Note: cameraPan is reused for box select, so no duplicate
    ],
    CameraPreset.platformer => [
      InputAction.moveLeft, // For panning
      InputAction.moveRight, // For panning
      InputAction.moveUp, // For panning
      InputAction.moveDown, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.jump, // Player action
      InputAction.attack, // Player action
    ],
    CameraPreset.topDown => [
      InputAction.moveLeft, // For panning
      InputAction.moveRight, // For panning
      InputAction.moveUp, // For panning
      InputAction.moveDown, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.jump, // Player action
    ],
    CameraPreset.isometric => [
      InputAction.cameraPan, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.cameraReset, // For reset
    ],
    CameraPreset.strategy => [
      InputAction.moveLeft, // For panning
      InputAction.moveRight, // For panning
      InputAction.moveUp, // For panning
      InputAction.moveDown, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.attack, // For single select
      // Note: cameraPan would be for box select but strategy uses movement keys
    ],
    CameraPreset.rpg => [
      InputAction.cameraPan, // For panning
      InputAction.zoomIn, // For zooming
      InputAction.zoomOut, // For zooming
      InputAction.jump, // Player action
      InputAction.interact, // Player action
    ],
  };
}
