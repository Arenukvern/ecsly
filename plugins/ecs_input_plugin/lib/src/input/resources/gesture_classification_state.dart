import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

import '../raw_input_events.dart';
import '../utils/gesture_types.dart';

/// Resource for tracking gesture state during classification.
///
/// Replaces GestureInputResource. Tracks pointer state to classify
/// raw events into gestures (tap, drag, long-press, etc.).
class GestureClassificationState extends Resource {
  /// Timeout for double-tap detection (300ms).
  static const _doubleTapTimeout = Duration(milliseconds: 300);

  /// Maximum distance between taps for double-tap detection (50px).
  static const _doubleTapDistanceThreshold = 50.0;

  /// Duration to display a completed gesture before showing 'none' (300ms).
  static const _gestureDisplayDuration = Duration(milliseconds: 300);

  final Map<int, PointerState> _pointers = {};

  /// Global history of recent taps for double-tap detection.
  ///
  /// Stores tap position and timestamp to enable cross-pointer double-tap detection.
  /// Cleaned periodically to prevent memory leaks.
  final List<_TapRecord> _recentTaps = [];

  /// Most recently completed gesture for display purposes.
  String? _mostRecentGesture;

  /// Timestamp when the most recent gesture was completed.
  DateTime? _mostRecentGestureTime;

  GestureClassificationState();
}

extension GestureClassificationStateOps on GestureClassificationState {
  void checkForDoubleTap(final RawPointerUpEvent event, final DateTime now) =>
      gestureCheckForDoubleTap(this, event, now);

  void checkLongPress(
    final DateTime now,
    final void Function(PointerState) callback,
  ) => gestureCheckLongPress(this, now, callback);

  GestureType classifyGesture(final int pointer, final DateTime now) =>
      gestureClassify(pointer, now, this);

  void cleanupStalePointers(final DateTime now) =>
      gestureCleanupStalePointers(this, now);

  String getCurrentGestureDisplay(final DateTime now) =>
      gestureCurrentGestureDisplay(this, now);

  Map<int, PointerState> getDraggingPointers() =>
      gestureGetDraggingPointers(this);

  ui.Offset getStartPosition(final int pointer) =>
      gestureStartPosition(this, pointer);

  ui.Offset getStartWorldPosition(final int pointer) =>
      gestureStartWorldPosition(this, pointer);

  bool hasActiveDragging() => gestureHasActiveDragging(this);

  bool isDragging(final int pointer) => gestureIsDragging(this, pointer);

  void onPointerCancel(final int pointer, final DateTime now) =>
      gestureOnPointerCancel(this, pointer);

  void onPointerDown(final RawPointerDownEvent event, final DateTime now) =>
      gestureOnPointerDown(this, event, now);

  void onPointerMove(final RawPointerMoveEvent event, final DateTime now) =>
      gestureOnPointerMove(this, event);

  void onPointerUp(final RawPointerUpEvent event, final DateTime now) =>
      gestureOnPointerUp(this, event);

  void recordCompletedGesture(final GestureType gesture, final DateTime now) =>
      gestureRecordCompleted(this, gesture, now);
}

void gestureCheckForDoubleTap(
  final GestureClassificationState state,
  final RawPointerUpEvent event,
  final DateTime now,
) {
  final pointerState = state._pointers[event.pointer];
  if (pointerState == null) return;

  final gesture = gestureClassify(event.pointer, now, state);
  if (gesture != GestureType.tap) return;

  gestureCleanupStaleTaps(state, now.millisecondsSinceEpoch);

  final currentPosition = event.worldPosition;
  final currentTimeMs = now.millisecondsSinceEpoch;

  for (final recentTap in state._recentTaps) {
    final timeDiff = currentTimeMs - recentTap.timestampMs;
    final distance = (currentPosition - recentTap.worldPosition).distance;

    if (timeDiff <=
            GestureClassificationState._doubleTapTimeout.inMilliseconds &&
        distance <= GestureClassificationState._doubleTapDistanceThreshold) {
      pointerState.isDoubleTap = true;
      break;
    }
  }

  state._recentTaps.add(
    _TapRecord(worldPosition: currentPosition, timestampMs: currentTimeMs),
  );
}

void gestureCheckLongPress(
  final GestureClassificationState state,
  final DateTime now,
  final void Function(PointerState) callback,
) {
  const longPressThreshold = Duration(milliseconds: 500);
  const dragThreshold = 5.0;

  for (final pointerState in state._pointers.values) {
    if (!pointerState.longPressTriggered &&
        now.difference(pointerState.startTime) >= longPressThreshold &&
        pointerState.totalDistance <= dragThreshold) {
      pointerState.longPressTriggered = true;
      callback(pointerState);
    }
  }
}

GestureType gestureClassify(
  final int pointer,
  final DateTime now,
  final GestureClassificationState state,
) {
  final pointerState = state._pointers[pointer];
  if (pointerState == null) return GestureType.none;

  final duration = now.difference(pointerState.startTime);
  const dragThreshold = 5.0;
  const longPressThreshold = Duration(milliseconds: 500);

  if (pointerState.isDoubleTap) {
    return GestureType.doubleTap;
  }

  if (pointerState.totalDistance <= dragThreshold) {
    if (duration < const Duration(milliseconds: 300)) {
      return GestureType.tap;
    } else if (duration >= longPressThreshold) {
      return GestureType.longPress;
    }
  }

  return GestureType.drag;
}

void gestureCleanupStalePointers(
  final GestureClassificationState state,
  final DateTime now,
) {
  const maxAge = Duration(seconds: 5);
  state._pointers.removeWhere(
    (final _, final pointerState) =>
        now.difference(pointerState.startTime) > maxAge,
  );
}

String gestureCurrentGestureDisplay(
  final GestureClassificationState state,
  final DateTime now,
) {
  for (final pointer in state._pointers.keys) {
    final gesture = gestureClassify(pointer, now, state);
    if (gesture == GestureType.none) continue;
    state._mostRecentGesture = gesture.name;
    state._mostRecentGestureTime = now;
    return gesture.name;
  }

  if (state._mostRecentGesture != null &&
      state._mostRecentGestureTime != null) {
    final timeSince = now.difference(state._mostRecentGestureTime!);
    if (timeSince <= GestureClassificationState._gestureDisplayDuration) {
      return state._mostRecentGesture!;
    }
  }

  return 'none';
}

Map<int, PointerState> gestureGetDraggingPointers(
  final GestureClassificationState state,
) {
  const threshold = 5.0;
  final dragging = <int, PointerState>{};
  for (final entry in state._pointers.entries) {
    if (entry.value.totalDistance > threshold) {
      dragging[entry.key] = entry.value;
    }
  }
  return dragging;
}

ui.Offset gestureStartPosition(
  final GestureClassificationState state,
  final int pointer,
) => state._pointers[pointer]?.startPosition ?? ui.Offset.zero;

ui.Offset gestureStartWorldPosition(
  final GestureClassificationState state,
  final int pointer,
) => state._pointers[pointer]?.startWorldPosition ?? ui.Offset.zero;

bool gestureHasActiveDragging(final GestureClassificationState state) {
  for (final pointer in state._pointers.keys) {
    if (gestureIsDragging(state, pointer)) return true;
  }
  return false;
}

bool gestureIsDragging(
  final GestureClassificationState state,
  final int pointer,
) {
  const threshold = 5.0;
  final pointerState = state._pointers[pointer];
  return pointerState != null && pointerState.totalDistance > threshold;
}

void gestureOnPointerCancel(
  final GestureClassificationState state,
  final int pointer,
) {
  state._pointers.remove(pointer);
}

void gestureOnPointerDown(
  final GestureClassificationState state,
  final RawPointerDownEvent event,
  final DateTime now,
) {
  state._pointers[event.pointer] = PointerState(
    startPosition: event.position,
    startWorldPosition: event.worldPosition,
    startTime: now,
    currentPosition: event.position,
    currentWorldPosition: event.worldPosition,
  );
}

void gestureOnPointerMove(
  final GestureClassificationState state,
  final RawPointerMoveEvent event,
) {
  final pointerState = state._pointers[event.pointer];
  if (pointerState == null) return;

  pointerState.currentPosition = event.position;
  pointerState.currentWorldPosition = event.worldPosition;
  pointerState.totalDistance =
      (event.position - pointerState.startPosition).distance;
}

void gestureOnPointerUp(
  final GestureClassificationState state,
  final RawPointerUpEvent event,
) {
  state._pointers.remove(event.pointer);
}

void gestureRecordCompleted(
  final GestureClassificationState state,
  final GestureType gesture,
  final DateTime now,
) {
  state._mostRecentGesture = gesture.name;
  state._mostRecentGestureTime = now;
}

void gestureCleanupStaleTaps(
  final GestureClassificationState state,
  final int nowMs,
) {
  state._recentTaps.removeWhere(
    (final tap) =>
        nowMs - tap.timestampMs >
        GestureClassificationState._doubleTapTimeout.inMilliseconds,
  );
}

class PointerState {
  final ui.Offset startPosition;

  final ui.Offset startWorldPosition;
  final DateTime startTime;
  ui.Offset currentPosition;
  ui.Offset currentWorldPosition;
  double totalDistance = 0;
  bool longPressTriggered = false;
  bool isDoubleTap = false;

  /// Whether drag-start selection has been processed for this pointer.
  ///
  /// Set to true when drag-start selection system processes selection
  /// for the first drag event from this pointer. Automatically cleared
  /// when pointer is released (PointerState is removed).
  bool dragStartSelectionProcessed = false;
  PointerState({
    required this.startPosition,
    required this.startWorldPosition,
    required this.startTime,
    required this.currentPosition,
    required this.currentWorldPosition,
  });
}

/// Record of a tap event for global double-tap detection.
///
/// Stores position and timestamp to enable spatial and temporal matching
/// across different pointer IDs.
class _TapRecord {
  final ui.Offset worldPosition;
  final int timestampMs;

  const _TapRecord({required this.worldPosition, required this.timestampMs});
}
