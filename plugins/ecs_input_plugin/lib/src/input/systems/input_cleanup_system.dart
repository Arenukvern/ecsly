import 'package:ecsly/ecsly.dart';

import '../resources/gesture_classification_state.dart';
import '../resources/input_state_tracker.dart';
import '../resources/selection_manager.dart';

/// System that performs end-of-frame cleanup for input resources.
///
/// This system runs in PostUpdate schedule and handles:
/// - Removing invalid entities from SelectionManager
/// - Cleaning up stale pointers from GestureClassificationState
/// - Advancing InputStateTracker to next frame
void inputCleanupSystem(final World world) {
  final now = DateTime.now();

  // Clean up invalid entities from selection manager
  final selectionManager = world.resources.has<SelectionManager>()
      ? world.getResource<SelectionManager>()
      : null;
  selectionManager?.removeInvalidEntities(world);

  // Clean up stale pointers from gesture classification state
  final gestureState = world.resources.has<GestureClassificationState>()
      ? world.getResource<GestureClassificationState>()
      : null;
  gestureState?.cleanupStalePointers(now);

  // Advance input state tracker to next frame
  final inputStateTracker = world.resources.has<InputStateTracker>()
      ? world.getResource<InputStateTracker>()
      : null;
  inputStateTracker?.advance();
}
