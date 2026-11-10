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

  double getAxis(final InputAction action) =>
      inputStateTrackerGetAxis(this, action);

  (double, double) getAxis2D(
    final InputAction up,
    final InputAction down,
    final InputAction left,
    final InputAction right,
  ) => inputStateTrackerGetAxis2D(this, up, down, left, right);

  InputState? getState(final InputAction action) =>
      inputStateTrackerGetState(this, action);

  bool isHeld(final InputAction action) =>
      inputStateTrackerIsHeld(this, action);

  bool justPressed(final InputAction action) =>
      inputStateTrackerJustPressed(this, action);

  bool justReleased(final InputAction action) =>
      inputStateTrackerJustReleased(this, action);

  void updateState(final InputAction action, final InputState state) =>
      inputStateTrackerUpdateState(this, action, state);
}

void inputStateTrackerAdvance(final InputStateTracker tracker) {
  developer.log('InputStateTracker.advance: ${tracker._currentStates}');
  tracker._previousStates
    ..clear()
    ..addAll(tracker._currentStates);

  tracker._currentStates.updateAll((final _, final state) {
    if (state == InputState.pressed) return InputState.held;
    if (state == InputState.released) return InputState.released;
    return state;
  });

  tracker._currentStates.removeWhere(
    (_, final state) => state == InputState.released,
  );
}

double inputStateTrackerGetAxis(
  final InputStateTracker tracker,
  final InputAction action,
) => inputStateTrackerIsHeld(tracker, action) ? 1.0 : 0.0;

(double, double) inputStateTrackerGetAxis2D(
  final InputStateTracker tracker,
  final InputAction up,
  final InputAction down,
  final InputAction left,
  final InputAction right,
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
  final InputStateTracker tracker,
  final InputAction action,
) => tracker._currentStates[action];

bool inputStateTrackerIsHeld(
  final InputStateTracker tracker,
  final InputAction action,
) {
  final state = tracker._currentStates[action];
  return state == InputState.pressed || state == InputState.held;
}

bool inputStateTrackerJustPressed(
  final InputStateTracker tracker,
  final InputAction action,
) => tracker._currentStates[action] == InputState.pressed;

bool inputStateTrackerJustReleased(
  final InputStateTracker tracker,
  final InputAction action,
) => tracker._currentStates[action] == InputState.released;

void inputStateTrackerUpdateState(
  final InputStateTracker tracker,
  final InputAction action,
  final InputState state,
) {
  final currentState = tracker._currentStates[action];
  if (currentState == state) return;

  tracker._currentStates[action] = state;
  developer.log('InputStateTracker.updateState: ${tracker._currentStates}');
}
