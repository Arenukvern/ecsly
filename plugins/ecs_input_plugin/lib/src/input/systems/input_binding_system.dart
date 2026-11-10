import 'dart:developer' as developer;

import 'package:ecsly/ecsly.dart';
import 'package:flutter/services.dart';

import '../events/input_action_event.dart';
import '../input_action.dart';
import '../resources/gesture_classification_state.dart';
import '../resources/input_source.dart';
import '../resources/input_state_tracker.dart';
import '../resources/runtime_input_map.dart';
import '../utils/gesture_types.dart';

/// System that processes raw input sources and emits action state events.
///
/// Reads RuntimeInputMap to determine source→action mappings,
/// then emits InputActionEvent for state changes.
void inputBindingSystem(final World world) {
  final inputMap = world.getResource<RuntimeInputMap>();
  final stateTracker = world.getResource<InputStateTracker>();
  final keyboard = HardwareKeyboard.instance;
  final pressedKeys = keyboard.logicalKeysPressed;

  // Developer logging: Log pressed keys
  if (pressedKeys.isNotEmpty) {
    developer.log(
      'Pressed keys: ${pressedKeys.map((final k) => k.keyLabel).join(', ')}',
      name: 'InputBindingSystem',
    );
  }

  // Track which actions are currently active from keyboard
  final activeActions = <InputAction>{};

  // 1. Process keyboard inputs
  for (final key in pressedKeys) {
    final matchingSources = inputMap.getMatchingKeyboardSources(
      key,
      pressedKeys,
    );
    for (final source in matchingSources) {
      final actions = inputMap.getActions(source);
      activeActions.addAll(actions);

      // Developer logging: Log action mappings
      if (actions.isNotEmpty) {
        developer.log(
          'Key ${key.keyLabel} -> Actions: ${actions.map((final a) => a.name).join(', ')}',
          name: 'InputBindingSystem',
        );
      }
    }
  }

  // 2. Process gesture inputs (check active drag state)
  // Check if any pointer is currently actively dragging to trigger camera pan
  final gestureState = world.getResource<GestureClassificationState>();
  if (gestureState.hasActiveDragging()) {
    const gestureSource = GestureSource(GestureType.drag);
    final actions = inputMap.getActions(gestureSource);
    activeActions.addAll(actions);

    // Developer logging: Log gesture actions
    if (actions.isNotEmpty) {
      developer.log(
        'Active drag gesture -> Actions: ${actions.map((final a) => a.name).join(', ')}',
        name: 'InputBindingSystem',
      );
    }
  }

  // Note: Scroll events are now processed by scrollInputSystem in the Input schedule

  // 3. Determine state transitions and emit events
  final writer = world.events.writer<InputActionEvent>();
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  for (final action in InputAction.values) {
    final wasActive = stateTracker.isHeld(action);
    final isActive = activeActions.contains(action);

    if (isActive && !wasActive) {
      // Newly pressed
      developer.log(
        'Action ${action.name}: pressed',
        name: 'InputBindingSystem',
      );
      writer.send(
        InputActionEvent(
          action: action,
          state: InputState.pressed,
          timestamp: timestamp,
        ),
      );
      stateTracker.updateState(action, InputState.pressed);
    } else if (!isActive && wasActive) {
      // Just released
      developer.log(
        'Action ${action.name}: released',
        name: 'InputBindingSystem',
      );
      writer.send(
        InputActionEvent(
          action: action,
          state: InputState.released,
          timestamp: timestamp,
        ),
      );
      stateTracker.updateState(action, InputState.released);
    }
  }
}
