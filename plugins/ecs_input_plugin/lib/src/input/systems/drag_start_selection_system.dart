import 'package:ecsly/ecsly.dart';

import '../draggable_components/interactive_element.dart';
import '../draggable_components/selectable_component.dart';
import '../gesture_events.dart';
import '../resources/gesture_classification_state.dart';
import '../resources/input_world_space_resource.dart';
import '../resources/selection_manager.dart';
import '../utils/hit_testing_utils.dart';

/// System that handles entity selection on drag start.
///
/// When a drag gesture starts (first time a pointer exceeds drag threshold),
/// this system checks if the drag started on a selectable entity. If so, it
/// selects the entity before entityDraggingSystem processes the drag.
///
/// This ensures that selection works even when small movements (>5px) cause the
/// gesture to be classified as a drag instead of a tap. This matches the behavior
/// of Unity, Unreal, and other ECS engines where selection happens on interaction
/// start, not just on pure taps.
///
/// **Execution Order:** This system must run after gestureClassificationSystem
/// (which tracks pointer state) but before entityDraggingSystem (which handles drags).
///
/// **Implementation:** Uses GestureClassificationState to track which pointers
/// have had drag-start selection processed. Reads [InputWorldSpaceResource] for
/// selection allowance and zoom (when absent: selection allowed, zoom = 1).
void dragStartSelectionSystem(final World world) {
  final worldSpace = world.resources.has<InputWorldSpaceResource>()
      ? world.getResource<InputWorldSpaceResource>()
      : null;
  if (worldSpace != null && !worldSpace.allowsEntitySelection) {
    return;
  }

  final selectionManager = world.resources.has<SelectionManager>()
      ? world.getResource<SelectionManager>()
      : null;

  if (selectionManager == null) {
    return; // No selection manager
  }

  final gestureState = world.resources.has<GestureClassificationState>()
      ? world.getResource<GestureClassificationState>()
      : null;

  if (gestureState == null) {
    return; // No gesture classification state
  }

  final double zoom = worldSpace?.zoom ?? 1.0;
  final now = DateTime.now();

  // Process active dragging pointers that haven't had drag-start selection processed
  final draggingPointers = gestureState.getDraggingPointers();
  for (final pointerState in draggingPointers.values) {
    // Skip if already processed
    if (pointerState.dragStartSelectionProcessed) {
      continue;
    }

    final entityAtStart = _findSelectableEntityAtPosition(
      world,
      pointerState.startWorldPosition.dx,
      pointerState.startWorldPosition.dy,
      zoom,
    );

    if (entityAtStart != null) {
      // Drag started on an entity - select it
      if (selectionManager.mode == SelectionMode.multi) {
        // Multi-select: toggle selection
        final wasSelected = selectionManager.isSelected(entityAtStart);
        selectionManager.toggleSelection(entityAtStart);
        final isNowSelected = selectionManager.isSelected(entityAtStart);

        // Dispatch event based on selection change
        if (!wasSelected && isNowSelected) {
          world.events.writer<EntitySelectedEvent>().send(
            EntitySelectedEvent(entity: entityAtStart, timestamp: now),
          );
        } else if (wasSelected && !isNowSelected) {
          world.events.writer<EntityDeselectedEvent>().send(
            EntityDeselectedEvent(entity: entityAtStart, timestamp: now),
          );
        }
      } else {
        // Single select: replace selection
        final previouslySelected = selectionManager.selectedEntities.toList();
        selectionManager.select(entityAtStart);

        // Dispatch deselected events for previously selected entities
        for (final prevEntity in previouslySelected) {
          if (prevEntity != entityAtStart) {
            world.events.writer<EntityDeselectedEvent>().send(
              EntityDeselectedEvent(entity: prevEntity, timestamp: now),
            );
          }
        }

        // Dispatch selected event for new selection
        world.events.writer<EntitySelectedEvent>().send(
          EntitySelectedEvent(entity: entityAtStart, timestamp: now),
        );
      }
    }

    // Mark as processed (whether entity was found or not)
    pointerState.dragStartSelectionProcessed = true;
  }
}

/// Find selectable entity at (worldX, worldY).
Entity? _findSelectableEntityAtPosition(
  final World world,
  final double worldX,
  final double worldY,
  final double currentZoom,
) {
  final candidates = <(Entity, int)>[];
  for (final (entity, interactive) in world.query<InteractiveElement>()) {
    final (ext, valid) = world.getEntity(entity.entity);
    if (!valid) continue;
    final selectable = ext.get<SelectableComponent>();
    if (selectable == null) continue;
    if (!selectable.canBeSelected(currentZoom)) continue;
    if (HitTestingUtils.testHit(
      entity.entity,
      interactive,
      worldX,
      worldY,
      world,
    )) {
      candidates.add((entity.entity, interactive.priority));
    }
  }

  // Sort by priority (descending) and return first match
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.$2.compareTo(a.$2));
  return candidates.first.$1;
}
