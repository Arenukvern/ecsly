import 'package:ecsly/ecsly.dart';

import '../input_action.dart';

/// Input state types.
enum InputState {
  /// Input just became active this frame.
  pressed,

  /// Input is being held (active for multiple frames).
  held,

  /// Input just became inactive this frame.
  released,
}

/// Input action event with state tracking.
class InputActionEvent extends TypedDataEvent with TypedDataEventMixin {
  InputActionEvent({
    required this.action,
    required this.state,
    required this.timestamp,
    this.value = 0.0, // For analog inputs (e.g., mouse delta, scroll amount)
  });

  final InputAction action;
  final InputState state;
  final int timestamp;
  final double value; // Future: axis values, scroll delta, etc.

  @override
  List<double> get numericFields => [
    action.index.toDouble(),
    state.index.toDouble(),
    timestamp.toDouble(),
    value,
  ];

  static InputActionEvent fromDoubleFields(final List<double> fields) {
    final actionIndex = fields[0].toInt();
    final stateIndex = fields[1].toInt();

    if (actionIndex < 0 || actionIndex >= InputAction.values.length) {
      throw ArgumentError('Invalid InputAction index: $actionIndex');
    }
    if (stateIndex < 0 || stateIndex >= InputState.values.length) {
      throw ArgumentError('Invalid InputState index: $stateIndex');
    }

    return InputActionEvent(
      action: InputAction.values[actionIndex],
      state: InputState.values[stateIndex],
      timestamp: fields[2].toInt(),
      value: fields[3],
    );
  }
}
