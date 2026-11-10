/// Scale gesture classification system.
///
/// Converts raw scale events (RawScaleUpdateEvent) into high-level pinch gestures (PinchEvent).
/// Provides world coordinate transformation and unified interface for camera zoom and UI scaling.
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../raw_input_events.dart';

/// Converts RawScaleUpdateEvent to PinchEvent.
///
/// Unlike pointer gestures (tap/drag) that require state tracking for
/// classification, scale gestures are already classified by Flutter's
/// GestureDetector. The world focal point comes from the host's
/// `toWorldCoords` converter when one is wired (RawScaleUpdateEvent
/// .worldFocalPoint), so camera systems can zoom at the cursor without
/// knowing the projection; without a converter it equals the screen focal.
/// scale/rotation stay CUMULATIVE (Flutter semantics) — consumers track
/// their own per-gesture deltas.
void scaleClassificationSystem(final World world) {
  // Process RawScaleUpdateEvent → PinchEvent conversion
  final updateReader = world.events.reader<RawScaleUpdateEvent>();
  for (final event in updateReader.iter()) {
    world.events.writer<PinchEvent>().send(
      PinchEvent(
        position: event.focalPoint,
        worldPosition: event.worldFocalPoint,
        scale: event.scale,
        focalPoint: event.focalPoint,
        focalPointDelta: event.focalPointDelta,
        rotation: event.rotation,
        pointerCount: event.pointerCount,
        timestamp: event.timestamp,
      ),
    );
  }

  // Process RawScaleEndEvent for cleanup (no-op for now)
  // RawScaleStartEvent is also processed for consistency but no state needed
  world.events.reader<RawScaleStartEvent>().iter();
  world.events.reader<RawScaleEndEvent>().iter();
}
