/// Scale gesture classification system.
///
/// Converts raw scale events (RawScaleUpdateEvent) into high-level pinch gestures (PinchEvent).
/// Provides world coordinate transformation and unified interface for camera zoom and UI scaling.
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../raw_input_events.dart';

/// Converts RawScaleUpdateEvent to PinchEvent with screen coordinates.
///
/// Unlike pointer gestures (tap/drag) that require state tracking for classification,
/// scale gestures are already classified by Flutter's GestureDetector. This system
/// emits PinchEvent with screen coordinates. Camera coordinate transformation is
/// handled by camera_control_plugin systems that consume PinchEvent.
void scaleClassificationSystem(final World world) {
  // Process RawScaleUpdateEvent → PinchEvent conversion
  final updateReader = world.events.reader<RawScaleUpdateEvent>();
  for (final event in updateReader.iter()) {
    // Emit PinchEvent with screen coordinates
    // Camera coordinate transformation is handled by camera_control_plugin systems
    final worldFocalPoint = event.focalPoint; // screen coordinates for now

    world.events.writer<PinchEvent>().send(
      PinchEvent(
        position: event.focalPoint,
        worldPosition: worldFocalPoint,
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
