/// Resource for tracking which gesture events have been consumed by entity handlers.
///
/// This enables background systems (like camera panning) to only process
/// events that weren't handled by interactive entities.
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';

/// Tracks consumption of gesture events for proper event propagation.
///
/// When an entity handles a gesture event (via EntityTapEvent, EntityDragEvent, etc.),
/// the corresponding global event is marked as consumed. Background systems can then
/// check if an event was consumed before processing it.
class GestureConsumptionTracker extends Resource {
  /// Set of consumed DragEvent indices (by timestamp for identification).
  final Set<int> _consumedDragEvents = {};

  /// Set of consumed TapEvent indices (by timestamp for identification).
  final Set<int> _consumedTapEvents = {};

  /// Set of consumed LongPressEvent indices (by timestamp for identification).
  final Set<int> _consumedLongPressEvents = {};

  /// Set of consumed SecondaryTapEvent indices (by timestamp for identification).
  final Set<int> _consumedSecondaryTapEvents = {};

  /// Set of consumed DoubleTapEvent indices (by timestamp for identification).
  final Set<int> _consumedDoubleTapEvents = {};

  /// Set of consumed PinchEvent indices (by timestamp for identification).
  final Set<int> _consumedPinchEvents = {};

  /// Set of consumed ScrollEvent indices (by timestamp for identification).
  final Set<int> _consumedScrollEvents = {};

  /// Clears all consumption tracking (called at end of frame).
  void clear() {
    _consumedDragEvents.clear();
    _consumedTapEvents.clear();
    _consumedLongPressEvents.clear();
    _consumedSecondaryTapEvents.clear();
    _consumedDoubleTapEvents.clear();
    _consumedPinchEvents.clear();
    _consumedScrollEvents.clear();
  }

  /// Checks if a DoubleTapEvent was consumed.
  bool isDoubleTapConsumed(final DoubleTapEvent event) =>
      _consumedDoubleTapEvents.contains(event.timestamp);

  /// Checks if a DragEvent was consumed.
  bool isDragConsumed(final DragEvent event) =>
      _consumedDragEvents.contains(event.timestamp);

  /// Checks if a LongPressEvent was consumed.
  bool isLongPressConsumed(final LongPressEvent event) =>
      _consumedLongPressEvents.contains(event.timestamp);

  /// Checks if a PinchEvent was consumed.
  bool isPinchConsumed(final PinchEvent event) =>
      _consumedPinchEvents.contains(event.timestamp);

  /// Checks if a ScrollEvent was consumed.
  bool isScrollConsumed(final ScrollEvent event) =>
      _consumedScrollEvents.contains(event.timestamp);

  /// Checks if a SecondaryTapEvent was consumed.
  bool isSecondaryTapConsumed(final SecondaryTapEvent event) =>
      _consumedSecondaryTapEvents.contains(event.timestamp);

  /// Checks if a TapEvent was consumed.
  bool isTapConsumed(final TapEvent event) =>
      _consumedTapEvents.contains(event.timestamp);

  /// Marks a DoubleTapEvent as consumed.
  void markDoubleTapConsumed(final DoubleTapEvent event) {
    _consumedDoubleTapEvents.add(event.timestamp);
  }

  /// Marks a DragEvent as consumed.
  void markDragConsumed(final DragEvent event) {
    _consumedDragEvents.add(event.timestamp);
  }

  /// Marks a LongPressEvent as consumed.
  void markLongPressConsumed(final LongPressEvent event) {
    _consumedLongPressEvents.add(event.timestamp);
  }

  /// Marks a PinchEvent as consumed.
  void markPinchConsumed(final PinchEvent event) {
    _consumedPinchEvents.add(event.timestamp);
  }

  /// Marks a ScrollEvent as consumed.
  void markScrollConsumed(final ScrollEvent event) {
    _consumedScrollEvents.add(event.timestamp);
  }

  /// Marks a SecondaryTapEvent as consumed.
  void markSecondaryTapConsumed(final SecondaryTapEvent event) {
    _consumedSecondaryTapEvents.add(event.timestamp);
  }

  /// Marks a TapEvent as consumed.
  void markTapConsumed(final TapEvent event) {
    _consumedTapEvents.add(event.timestamp);
  }
}
