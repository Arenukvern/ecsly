/// Event clearing system.
///
/// Clears all input events at the end of the input processing frame.
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../raw_input_events.dart';
import '../resources/gesture_consumption_tracker.dart';

void eventInputClearSystem(final World world) {
  // Consume any remaining events to prevent them from persisting
  world.events.reader<TapEvent>().iter();
  world.events.reader<DoubleTapEvent>().iter();
  world.events.reader<LongPressEvent>().iter();
  world.events.reader<DragEvent>().iter();
  world.events.reader<PinchEvent>().iter();
  world.events.reader<ScrollEvent>().iter();
  world.events.reader<SecondaryTapEvent>().iter();
  world.events.reader<EntityTapEvent>().iter();
  world.events.reader<EntityDragEvent>().iter();
  world.events.reader<EntityLongPressEvent>().iter();
  world.events.reader<RawKeyDownEvent>().iter();
  world.events.reader<RawKeyUpEvent>().iter();
  world.events.reader<RawKeyRepeatEvent>().iter();
  world.events.reader<RawPointerDownEvent>().iter();
  world.events.reader<RawPointerUpEvent>().iter();
  world.events.reader<RawPointerMoveEvent>().iter();
  world.events.reader<RawPointerHoverEvent>().iter();
  world.events.reader<RawPointerCancelEvent>().iter();
  world.events.reader<RawScaleStartEvent>().iter();
  world.events.reader<RawScaleUpdateEvent>().iter();
  world.events.reader<RawScaleEndEvent>().iter();

  world.events.clearAll();

  // Clear consumption tracking for next frame
  if (world.resources.has<GestureConsumptionTracker>()) {
    world.getResource<GestureConsumptionTracker>().clear();
  }
}
