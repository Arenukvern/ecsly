/// Secondary tap input system.
///
/// Processes SecondaryTapEvent events, performs hit testing on interactive entities,
/// and handles background secondary tap (typically context menus).
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../resources/interactive_entities_cache.dart';
import '../utils/gesture_types.dart';
import '../utils/hit_testing.dart';

void secondaryTapInputSystem(final World world) {
  final secondaryTapReader = world.events.reader<SecondaryTapEvent>();
  final entityWriter = world.events.writer<EntitySecondaryTapEvent>();
  final cache = world.getResource<InteractiveEntitiesCache>();

  // Get cached interactive entities sorted by priority
  final interactives = cache.getEntities(world);

  for (final secondaryTapEvent in secondaryTapReader.iter()) {
    var handled = false;

    // Hit test interactive entities in priority order
    for (final (entity, interactive) in interactives) {
      if (hitTest(
        secondaryTapEvent.worldPosition.dx,
        secondaryTapEvent.worldPosition.dy,
        entity,
        world,
      )) {
        // Check if entity supports secondary tap gestures
        if (interactive.supportedGestures.contains(GestureType.secondaryTap) ||
            interactive.supportedGestures.contains(GestureType.none)) {
          // For now, send as long-press event (applications can differentiate)
          entityWriter.send(
            EntitySecondaryTapEvent(
              entity: entity,
              position: secondaryTapEvent.position,
              worldPosition: secondaryTapEvent.worldPosition,
              timestamp: secondaryTapEvent.timestamp,
            ),
          );

          handled = true;
          // Stop propagation if entity blocks it
          if (interactive.blocksPropagation) {
            break;
          }
        }
      }
    }

    // If not handled by any entity, handle as background secondary tap
    if (!handled) {
      // Background secondary tap - could show global context menu
      // Graceful handling: no action needed, event is consumed
    }
  }
}
