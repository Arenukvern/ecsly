import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';

import '../events/input_action_event.dart';
import '../input_action.dart';

/// Resource that tracks current state of each input.
class InputStateTracker extends Resource {
  /// Current frame's input states.
  final Map<InputAction, InputState> _currentStates = {};

  /// Previous frame's input states (for detecting state transitions).
  final Map<InputAction, InputState> _previousStates = {};
}

extension InputStateTrackerOps on InputStateTracker {
  void advance() => inputStateTrackerAdvance(this);

  double getAxis(InputAction action) =>
      inputStateTrackerGetAxis(this, action);

  (double, double) getAxis2D(
    InputAction up,
    InputAction down,
    InputAction left,
    InputAction right,
  ) => inputStateTrackerGetAxis2D(this, up, down, left, right);

  InputState? getState(InputAction action) =>
      inputStateTrackerGetState(this, action);

  bool isHeld(InputAction action) =>
      inputStateTrackerIsHeld(this, action);

  bool justPressed(InputAction action) =>
      inputStateTrackerJustPressed(this, action);

  bool justReleased(InputAction action) =>
      inputStateTrackerJustReleased(this, action);

  void updateState(InputAction action, InputState state) =>
      inputStateTrackerUpdateState(this, action, state);
}

void inputStateTrackerAdvance(InputStateTracker tracker) {
  developer.log('InputStateTracker.advance: ${tracker._currentStates}');
  tracker._previousStates
    ..clear()
    ..addAll(tracker._currentStates);

  tracker._currentStates.updateAll((_, state) {
    if (state == InputState.pressed) return InputState.held;
    if (state == InputState.released) return InputState.released;
    return state;
  });

  tracker._currentStates.removeWhere(
    (_, state) => state == InputState.released,
  );
}

double inputStateTrackerGetAxis(
  InputStateTracker tracker,
  InputAction action,
) => inputStateTrackerIsHeld(tracker, action) ? 1.0 : 0.0;

(double, double) inputStateTrackerGetAxis2D(
  InputStateTracker tracker,
  InputAction up,
  InputAction down,
  InputAction left,
  InputAction right,
) {
  var x = 0.0;
  var y = 0.0;

  if (inputStateTrackerIsHeld(tracker, right)) x += 1.0;
  if (inputStateTrackerIsHeld(tracker, left)) x -= 1.0;
  if (inputStateTrackerIsHeld(tracker, up)) y += 1.0;
  if (inputStateTrackerIsHeld(tracker, down)) y -= 1.0;

  if (x != 0.0 && y != 0.0) {
    final length = math.sqrt(x * x + y * y);
    x /= length;
    y /= length;
  }

  return (x, y);
}

InputState? inputStateTrackerGetState(
  InputStateTracker tracker,
  InputAction action,
) => tracker._currentStates[action];

bool inputStateTrackerIsHeld(
  InputStateTracker tracker,
  InputAction action,
) {
  final state = tracker._currentStates[action];
  return state == InputState.pressed || state == InputState.held;
}

bool inputStateTrackerJustPressed(
  InputStateTracker tracker,
  InputAction action,
) => tracker._currentStates[action] == InputState.pressed;

bool inputStateTrackerJustReleased(
  InputStateTracker tracker,
  InputAction action,
) => tracker._currentStates[action] == InputState.released;

void inputStateTrackerUpdateState(
  InputStateTracker tracker,
  InputAction action,
  InputState state,
) {
  final currentState = tracker._currentStates[action];
  if (currentState == state) return;

  tracker._currentStates[action] = state;
  developer.log('InputStateTracker.updateState: ${tracker._currentStates}');
}
