import '../input_action.dart';
import '../resources/runtime_input_map.dart';

/// Result of input configuration validation.
class InputConfigValidationResult {
  /// Creates a result of input configuration validation.
  const InputConfigValidationResult({
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

/// Validates input configuration.
///
/// Note: Camera preset validation has been moved to CameraControlPlugin.
/// This validator focuses on general input configuration validation.
class InputConfigValidator {
  /// Validate that required actions are bound.
  ///
  /// [requiredActions] List of actions that must be bound
  /// [inputMap] Input map to check for bindings
  /// Returns validation result with missing bindings if any
  InputConfigValidationResult validateActions(
    final List<InputAction> requiredActions,
    final RuntimeInputMap inputMap,
  ) {
    final missingBindings = <InputAction>[];

    for (final action in requiredActions) {
      if (inputMap.getSources(action).isEmpty) {
        missingBindings.add(action);
      }
    }

    return InputConfigValidationResult(
      isValid: missingBindings.isEmpty,
      missingBindings: missingBindings,
    );
  }
}
