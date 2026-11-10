import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../raw_input_events.dart';
import '../resources/gesture_classification_state.dart';
import '../utils/gesture_types.dart';

/// Classifies raw pointer events into high-level gestures.
///
/// Replaces logic previously in UnifiedInputWidget.
/// Processes raw events and emits classified gesture events (tap, drag, long-press, etc.).
void gestureClassificationSystem(final World world) {
  final state = world.getResource<GestureClassificationState>();
  final now = DateTime.now();

  // Clean up stale pointers that went off-screen
  state.cleanupStalePointers(now);

  // Process pointer down events
  final downReader = world.events.reader<RawPointerDownEvent>();
  for (final event in downReader.iter()) {
    state.onPointerDown(event, now);
  }

  // Process pointer move events
  final moveReader = world.events.reader<RawPointerMoveEvent>();
  for (final event in moveReader.iter()) {
    state.onPointerMove(event, now);

    // Emit drag events if threshold exceeded
    if (state.isDragging(event.pointer)) {
      world.events.writer<DragEvent>().send(
        DragEvent(
          position: event.position,
          worldPosition: event.worldPosition,
          startPosition: state.getStartPosition(event.pointer),
          startWorldPosition: state.getStartWorldPosition(event.pointer),
          delta: event.delta,
          timestamp: event.timestamp,
          buttons: event.buttons,
          modifierMask: event.modifierMask,
        ),
      );
    }
  }

  // Process pointer up events
  final upReader = world.events.reader<RawPointerUpEvent>();
  for (final event in upReader.iter()) {
    // Check for double-tap first (sets isDoubleTap flag)
    state.checkForDoubleTap(event, now);

    // Classify final gesture
    final gesture = state.classifyGesture(event.pointer, now);

    switch (gesture) {
      case GestureType.tap:
        world.events.writer<TapEvent>().send(
          TapEvent(
            position: event.position,
            worldPosition: event.worldPosition,
            timestamp: event.timestamp,
          ),
        );
        state.recordCompletedGesture(GestureType.tap, now);
      case GestureType.doubleTap:
        world.events.writer<DoubleTapEvent>().send(
          DoubleTapEvent(
            position: event.position,
            worldPosition: event.worldPosition,
            timestamp: event.timestamp,
          ),
        );
        state.recordCompletedGesture(GestureType.doubleTap, now);
      case GestureType.longPress:
        // Already sent during move, but record for display
        state.recordCompletedGesture(GestureType.longPress, now);
        break;
      case GestureType.drag:
        // Record drag completion on pointer up (drag ended)
        state.recordCompletedGesture(GestureType.drag, now);
        break;
      default:
        break;
    }

    state.onPointerUp(event, now);
  }

  // Handle pointer cancel events
  final cancelReader = world.events.reader<RawPointerCancelEvent>();
  for (final event in cancelReader.iter()) {
    state.onPointerCancel(event.pointer, now);
  }

  // Handle long-press detection
  state.checkLongPress(now, (final pointerState) {
    world.events.writer<LongPressEvent>().send(
      LongPressEvent(
        position: pointerState.currentPosition,
        worldPosition: pointerState.currentWorldPosition,
        timestamp: now.millisecondsSinceEpoch,
      ),
    );
  });
}
