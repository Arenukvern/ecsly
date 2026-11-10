import 'package:ecsly/ecsly.dart';

import '../draggable_components/interactive_element.dart';
import '../draggable_components/selectable_component.dart';
import '../gesture_events.dart';
import '../resources/input_world_space_resource.dart';
import '../resources/selection_manager.dart';
import '../utils/hit_testing_utils.dart';

/// Entity selection system for tap-based entity selection.
///
/// Handles TapEvent events to select/deselect entities when interaction mode allows it.
/// Uses SelectionManager to manage selection state and dispatches EntitySelectedEvent/EntityDeselectedEvent.
/// Renders use SelectionHighlightComponent for visual feedback (component is persistent configuration).
///
/// Features:
/// - Reads zoom and allowsEntitySelection from [InputWorldSpaceResource] (written by camera/control or host)
/// - Priority-ordered hit testing (higher priority entities selected first)
/// - Event-driven architecture for reactive systems
/// - When [InputWorldSpaceResource] is absent: zoom = 1, selection allowed
///
/// @ai Hit testing sorts entities by InteractiveElement.priority before selection.
/// SelectionManager provides O(1) lookup without archetype fragmentation.
void entitySelectionSystem(final World world) {
  final tapReader = world.events.reader<TapEvent>();

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
    return; // No selection manager resource
  }

  final double zoom = worldSpace?.zoom ?? 1.0;

  // Process tap events for entity selection
  for (final tapEvent in tapReader.iter()) {
    final tappedEntity = _findSelectableEntityAtPosition(
      world,
      tapEvent.worldPosition.dx,
      tapEvent.worldPosition.dy,
      zoom,
    );

    if (tappedEntity != null) {
      // Entity was tapped - handle selection
      if (selectionManager.mode == SelectionMode.multi) {
        // Multi-select: toggle selection
        final wasSelected = selectionManager.isSelected(tappedEntity);
        selectionManager.toggleSelection(tappedEntity);
        final isNowSelected = selectionManager.isSelected(tappedEntity);

        // Dispatch event based on selection change
        if (!wasSelected && isNowSelected) {
          world.events.writer<EntitySelectedEvent>().send(
            EntitySelectedEvent(
              entity: tappedEntity,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                tapEvent.timestamp,
              ),
            ),
          );
        } else if (wasSelected && !isNowSelected) {
          world.events.writer<EntityDeselectedEvent>().send(
            EntityDeselectedEvent(
              entity: tappedEntity,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                tapEvent.timestamp,
              ),
            ),
          );
        }
      } else {
        // Single select: replace selection
        final previouslySelected = selectionManager.selectedEntities.toList();
        selectionManager.select(tappedEntity);

        // Dispatch deselected events for previously selected entities
        for (final prevEntity in previouslySelected) {
          if (prevEntity != tappedEntity) {
            world.events.writer<EntityDeselectedEvent>().send(
              EntityDeselectedEvent(
                entity: prevEntity,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  tapEvent.timestamp,
                ),
              ),
            );
          }
        }

        // Dispatch selected event for new selection
        world.events.writer<EntitySelectedEvent>().send(
          EntitySelectedEvent(
            entity: tappedEntity,
            timestamp: DateTime.fromMillisecondsSinceEpoch(tapEvent.timestamp),
          ),
        );
      }
    } else {
      // Tapped empty space - clear selection
      final previouslySelected = selectionManager.selectedEntities.toList();
      selectionManager.clearSelection();

      // Dispatch deselected events for all previously selected entities
      for (final prevEntity in previouslySelected) {
        world.events.writer<EntityDeselectedEvent>().send(
          EntityDeselectedEvent(
            entity: prevEntity,
            timestamp: DateTime.fromMillisecondsSinceEpoch(tapEvent.timestamp),
          ),
        );
      }
    }
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
