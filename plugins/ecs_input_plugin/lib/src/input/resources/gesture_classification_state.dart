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
  void checkForDoubleTap(RawPointerUpEvent event, DateTime now) =>
      gestureCheckForDoubleTap(this, event, now);

  void checkLongPress(
    DateTime now,
    void Function(PointerState) callback,
  ) => gestureCheckLongPress(this, now, callback);

  GestureType classifyGesture(int pointer, DateTime now) =>
      gestureClassify(pointer, now, this);

  void cleanupStalePointers(DateTime now) =>
      gestureCleanupStalePointers(this, now);

  String getCurrentGestureDisplay(DateTime now) =>
      gestureCurrentGestureDisplay(this, now);

  Map<int, PointerState> getDraggingPointers() =>
      gestureGetDraggingPointers(this);

  ui.Offset getStartPosition(int pointer) =>
      gestureStartPosition(this, pointer);

  ui.Offset getStartWorldPosition(int pointer) =>
      gestureStartWorldPosition(this, pointer);

  bool hasActiveDragging() => gestureHasActiveDragging(this);

  bool isDragging(int pointer) => gestureIsDragging(this, pointer);

  void onPointerCancel(int pointer, DateTime now) =>
      gestureOnPointerCancel(this, pointer);

  void onPointerDown(RawPointerDownEvent event, DateTime now) =>
      gestureOnPointerDown(this, event, now);

  void onPointerMove(RawPointerMoveEvent event, DateTime now) =>
      gestureOnPointerMove(this, event);

  void onPointerUp(RawPointerUpEvent event, DateTime now) =>
      gestureOnPointerUp(this, event);

  void recordCompletedGesture(GestureType gesture, DateTime now) =>
      gestureRecordCompleted(this, gesture, now);
}

void gestureCheckForDoubleTap(
  GestureClassificationState state,
  RawPointerUpEvent event,
  DateTime now,
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
  GestureClassificationState state,
  DateTime now,
  void Function(PointerState) callback,
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
  int pointer,
  DateTime now,
  GestureClassificationState state,
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
  GestureClassificationState state,
  DateTime now,
) {
  const maxAge = Duration(seconds: 5);
  state._pointers.removeWhere(
    (_, pointerState) =>
        now.difference(pointerState.startTime) > maxAge,
  );
}

String gestureCurrentGestureDisplay(
  GestureClassificationState state,
  DateTime now,
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
  GestureClassificationState state,
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
  GestureClassificationState state,
  int pointer,
) => state._pointers[pointer]?.startPosition ?? ui.Offset.zero;

ui.Offset gestureStartWorldPosition(
  GestureClassificationState state,
  int pointer,
) => state._pointers[pointer]?.startWorldPosition ?? ui.Offset.zero;

bool gestureHasActiveDragging(GestureClassificationState state) {
  for (final pointer in state._pointers.keys) {
    if (gestureIsDragging(state, pointer)) return true;
  }
  return false;
}

bool gestureIsDragging(
  GestureClassificationState state,
  int pointer,
) {
  const threshold = 5.0;
  final pointerState = state._pointers[pointer];
  return pointerState != null && pointerState.totalDistance > threshold;
}

void gestureOnPointerCancel(
  GestureClassificationState state,
  int pointer,
) {
  state._pointers.remove(pointer);
}

void gestureOnPointerDown(
  GestureClassificationState state,
  RawPointerDownEvent event,
  DateTime now,
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
  GestureClassificationState state,
  RawPointerMoveEvent event,
) {
  final pointerState = state._pointers[event.pointer];
  if (pointerState == null) return;

  pointerState.currentPosition = event.position;
  pointerState.currentWorldPosition = event.worldPosition;
  pointerState.totalDistance =
      (event.position - pointerState.startPosition).distance;
}

void gestureOnPointerUp(
  GestureClassificationState state,
  RawPointerUpEvent event,
) {
  state._pointers.remove(event.pointer);
}

void gestureRecordCompleted(
  GestureClassificationState state,
  GestureType gesture,
  DateTime now,
) {
  state._mostRecentGesture = gesture.name;
  state._mostRecentGestureTime = now;
}

void gestureCleanupStaleTaps(
  GestureClassificationState state,
  int nowMs,
) {
  state._recentTaps.removeWhere(
    (tap) =>
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
