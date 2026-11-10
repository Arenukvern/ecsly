/// Double-tap input system (separate from tap for clarity).
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../resources/interactive_entities_cache.dart';
import '../utils/gesture_types.dart';
import '../utils/hit_testing.dart';

void doubleTapInputSystem(final World world) {
  final doubleTapReader = world.events.reader<DoubleTapEvent>();
  final entityWriter = world.events.writer<EntityTapEvent>();
  final cache = world.getResource<InteractiveEntitiesCache>();

  // Get cached interactive entities sorted by priority
  final interactives = cache.getEntities(world);

  for (final doubleTapEvent in doubleTapReader.iter()) {
    // Hit test interactive entities in priority order
    for (final (entity, interactive) in interactives) {
      if (hitTest(
        doubleTapEvent.worldPosition.dx,
        doubleTapEvent.worldPosition.dy,
        entity,
        world,
      )) {
        // Check if entity supports double-tap gestures
        if (interactive.supportedGestures.contains(GestureType.doubleTap) ||
            interactive.supportedGestures.contains(GestureType.none)) {
          // Send entity-specific tap event (applications can check tapCount)
          entityWriter.send(
            EntityTapEvent(
              entity: entity,
              position: doubleTapEvent.position,
              worldPosition: doubleTapEvent.worldPosition,
              timestamp: doubleTapEvent.timestamp,
            ),
          );

          // Stop propagation if entity blocks it
          if (interactive.blocksPropagation) {
            break;
          }
        }
      }
    }
  }
}
