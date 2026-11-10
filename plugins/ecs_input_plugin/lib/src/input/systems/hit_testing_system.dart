/// Unified hit testing system that processes all gesture events.
///
/// This system eliminates code duplication by centralizing hit testing logic
/// for all input gesture types. It processes gesture events, performs hit testing
/// on cached interactive entities, and dispatches appropriate entity-specific events.
///
/// Performance: O(n*m) where n=gesture events, m=interactive entities
/// but with caching, m is constant until world changes.
library;

import 'package:ecsly/ecsly.dart';

import '../draggable_components/hit_shape.dart';
import '../draggable_components/interactive_element.dart';
import '../gesture_events.dart';
import '../resources/gesture_consumption_tracker.dart';
import '../resources/interactive_entities_cache.dart';
import '../utils/entity_world_position.dart';
import '../utils/gesture_types.dart';

/// Unified hit testing system for all gesture events.
///
/// Processes TapEvent, DragEvent, LongPressEvent, SecondaryTapEvent, DoubleTapEvent
/// and dispatches corresponding EntityTapEvent, EntityDragEvent, etc. to hit entities.
void unifiedHitTestingSystem(final World world) {
  // Get cached interactive entities sorted by priority
  final cache = world.getResource<InteractiveEntitiesCache>();
  final interactives = cache.getEntities(world);

  // Process tap events
  _processGestureEvents<TapEvent, EntityTapEvent>(
    world: world,
    interactives: interactives,
    gestureType: GestureType.tap,
    createEntityEvent: (final entity, final event) => EntityTapEvent(
      entity: entity,
      position: event.position,
      worldPosition: event.worldPosition,
      timestamp: event.timestamp,
    ),
  );

  // Process drag events
  _processGestureEvents<DragEvent, EntityDragEvent>(
    world: world,
    interactives: interactives,
    gestureType: GestureType.drag,
    createEntityEvent: (final entity, final event) => EntityDragEvent(
      entity: entity,
      position: event.position,
      worldPosition: event.worldPosition,
      delta: event.delta,
      timestamp: event.timestamp,
    ),
  );

  // Process long press events
  _processGestureEvents<LongPressEvent, EntityLongPressEvent>(
    world: world,
    interactives: interactives,
    gestureType: GestureType.longPress,
    createEntityEvent: (final entity, final event) => EntityLongPressEvent(
      entity: entity,
      position: event.position,
      worldPosition: event.worldPosition,
      timestamp: event.timestamp,
    ),
  );

  // Process secondary tap events
  _processGestureEvents<SecondaryTapEvent, EntitySecondaryTapEvent>(
    world: world,
    interactives: interactives,
    gestureType: GestureType.secondaryTap,
    createEntityEvent: (final entity, final event) => EntitySecondaryTapEvent(
      entity: entity,
      position: event.position,
      worldPosition: event.worldPosition,
      timestamp: event.timestamp,
    ),
  );

  // Process double tap events (dispatch as EntityTapEvent)
  _processGestureEvents<DoubleTapEvent, EntityTapEvent>(
    world: world,
    interactives: interactives,
    gestureType: GestureType.doubleTap,
    createEntityEvent: (final entity, final event) => EntityTapEvent(
      entity: entity,
      position: event.position,
      worldPosition: event.worldPosition,
      timestamp: event.timestamp,
    ),
  );
}

/// Hit test (pointerWorldX, pointerWorldY) against entity (pure doubles).
bool _hitTest(
  final double pointerWorldX,
  final double pointerWorldY,
  final Entity entity,
  final World world,
) {
  final position = extractEntityWorldPosition(entity, world);
  if (position == null) return false;
  final interactive = world.getEntity(entity).$1.get<InteractiveElement>();
  if (interactive == null) return false;
  final shape = interactive.hitShape;
  final (cx, cy) = position;
  switch (shape.type) {
    case HitShapeType.circle:
      final radius = shape.radius ?? 0.0;
      final dx = pointerWorldX - cx;
      final dy = pointerWorldY - cy;
      return dx * dx + dy * dy <= radius * radius;
    case HitShapeType.rectangle:
      final width = shape.width ?? 0.0;
      final height = shape.height ?? 0.0;
      final halfW = width / 2;
      final halfH = height / 2;
      return pointerWorldX >= cx - halfW &&
          pointerWorldX <= cx + halfW &&
          pointerWorldY >= cy - halfH &&
          pointerWorldY <= cy + halfH;
  }
}

/// Marks a gesture event as consumed in the tracker.
void _markEventConsumed(
  final GestureConsumptionTracker tracker,
  final GestureEvent event,
) {
  switch (event) {
    case DragEvent():
      tracker.markDragConsumed(event);
    case TapEvent():
      tracker.markTapConsumed(event);
    case LongPressEvent():
      tracker.markLongPressConsumed(event);
    case SecondaryTapEvent():
      tracker.markSecondaryTapConsumed(event);
    case DoubleTapEvent():
      // Double-tap events are consumed by hit testing to prevent conflicts with
      // single-tap selection when users rapidly tap twice
      tracker.markDoubleTapConsumed(event);
    case EntityDragEvent():
      // Entity drag events are consumed to prevent camera panning during
      // entity dragging operations, ensuring smooth drag behavior
      // Note: Entity events consume the corresponding global events they were derived from
      break;
    case EntityTapEvent():
      // Entity tap events are consumed to prevent camera interactions when
      // tapping on entities, allowing proper entity selection
      // Note: Entity events consume the corresponding global events they were derived from
      break;
    case EntityLongPressEvent():
      // Entity long-press events are consumed to prevent camera zoom or other
      // interactions when performing long-press actions on entities
      // Note: Entity events consume the corresponding global events they were derived from
      break;
    case EntitySecondaryTapEvent():
      // Entity secondary tap events (right-click) are consumed to prevent
      // default browser/context menu behavior during entity interactions
      // Note: Entity events consume the corresponding global events they were derived from
      break;
    case PinchEvent():
      // Pinch events are consumed to prevent browser zoom when performing
      // camera zoom gestures in the game world
      tracker.markPinchConsumed(event);
    case ScrollEvent():
      // Scroll events are consumed to prevent page scrolling when performing
      // camera zoom with mouse wheel in the game world
      tracker.markScrollConsumed(event);
  }
}

/// Generic helper to process gesture events of a specific type.
void _processGestureEvents<
  TGestureEvent extends GestureEvent,
  TEntityEvent extends TypedDataEvent
>({
  required final World world,
  required final List<(Entity, InteractiveElement)> interactives,
  required final GestureType gestureType,
  required final TEntityEvent Function(Entity, TGestureEvent) createEntityEvent,
}) {
  final gestureReader = world.events.reader<TGestureEvent>();
  final entityWriter = world.events.writer<TEntityEvent>();

  // Get consumption tracker (create if needed)
  if (!world.resources.has<GestureConsumptionTracker>()) {
    world.resources.push(GestureConsumptionTracker());
  }
  final tracker = world.getResource<GestureConsumptionTracker>();

  for (final gestureEvent in gestureReader.iter()) {
    // Hit test interactive entities in priority order
    for (final (entity, interactive) in interactives) {
      if (_hitTest(
        gestureEvent.worldPosition.dx,
        gestureEvent.worldPosition.dy,
        entity,
        world,
      )) {
        // Check if entity supports this gesture type
        if (interactive.supportedGestures.contains(gestureType) ||
            interactive.supportedGestures.contains(GestureType.none)) {
          // Dispatch entity-specific event
          entityWriter.send(createEntityEvent(entity, gestureEvent));

          // Mark event as consumed
          _markEventConsumed(tracker, gestureEvent);

          // Stop propagation if entity blocks it
          if (interactive.blocksPropagation) {
            break;
          }
        }
      }
    }
  }
}
