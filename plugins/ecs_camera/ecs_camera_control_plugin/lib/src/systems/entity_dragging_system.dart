import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

import '../resources/camera_interaction_mode_resource.dart';

/// Entity dragging system for moving selected entities.
///
/// Handles DragEvent events to move selected entities when interaction mode allows it.
/// Only works in multi-mode where entity dragging is permitted.
/// Priority goes to entity dragging over camera panning when entities are selected.
///
/// @ai This system consumes drag events when dragging entities.
/// It only runs when [CameraInteractionModeResource.allowsEntityDragging] is true
/// and entities are currently selected.
///
/// Note: Works without camera plugin. Uses zoom = 1.0 when camera is not available.
void entityDraggingSystem(final World world) {
  final dragReader = world.events.reader<DragEvent>();

  // Check if entity dragging is enabled in current interaction mode
  final modeResource = world.resources.has<CameraInteractionModeResource>()
      ? world.getResource<CameraInteractionModeResource>()
      : null;

  if (modeResource == null || !modeResource.allowsEntityDragging) {
    return; // Entity dragging disabled or not allowed in current mode
  }

  final selectionManager = world.resources.has<SelectionManager>()
      ? world.getResource<SelectionManager>()
      : null;

  if (selectionManager == null || !selectionManager.hasSelection) {
    return; // No selection manager or nothing selected
  }

  // Get current camera zoom for proper drag scaling
  final double zoom = getCameraZoom(world);

  final tracker = world.resources.has<GestureConsumptionTracker>()
      ? world.getResource<GestureConsumptionTracker>()
      : null;

  // Get all selected draggable entities (regardless of position)
  final allSelectedDraggableEntities = _getAllSelectedDraggableEntities(
    world,
    selectionManager,
  );

  // If we have selected draggable entities, consume all drag events
  if (allSelectedDraggableEntities.isNotEmpty) {
    for (final dragEvent in dragReader.iter()) {
      // Skip if event was already consumed
      if (tracker != null && tracker.isDragConsumed(dragEvent)) {
        continue;
      }

      // Mark event as consumed to prevent camera panning
      if (tracker != null) {
        tracker.markDragConsumed(dragEvent);
      }

      // Apply drag to all selected draggable entities
      // Divide by zoom to convert screen delta to world delta
      final deltaX = dragEvent.delta.dx / zoom;
      final deltaY = dragEvent.delta.dy / zoom;

      for (final entity in allSelectedDraggableEntities) {
        _applyDragToEntity(world, entity, deltaX, deltaY);
      }
    }
  }
}

/// Apply drag movement to an entity.
///
/// [world] ECS world
/// [entity] Entity to move
/// [deltaX] X movement delta (world units)
/// [deltaY] Y movement delta (world units)
void _applyDragToEntity(
  final World world,
  final Entity entity,
  final double deltaX,
  final double deltaY,
) {
  final (worldEntity, isValid) = world.getEntity(entity);
  if (!isValid) return;
  final draggable = worldEntity.get<DraggableComponent>();
  if (draggable == null) return;

  // Apply drag constraints to movement delta
  final (constrainedX, constrainedY) = draggable.constrainDelta(deltaX, deltaY);

  if (world.resources.has<PositionConfigResource>()) {
    final config = world.getResource<PositionConfigResource>();
    applyPositionDelta(world, entity, constrainedX, constrainedY, config);
  }
}

/// Get all selected draggable entities.
///
/// [world] ECS world
/// [selectionManager] Current selection manager
/// Returns list of all draggable selected entities
List<Entity> _getAllSelectedDraggableEntities(
  final World world,
  final SelectionManager selectionManager,
) {
  final draggableEntities = <Entity>[];

  for (final selectedEntity in selectionManager.selectedEntities) {
    // Check if entity is draggable
    final (entityExt, isValid) = world.getEntity(selectedEntity);
    if (!isValid) continue;

    final draggable = entityExt.get<DraggableComponent>();

    if (draggable != null && draggable.canBeDragged) {
      draggableEntities.add(selectedEntity);
    }
  }

  return draggableEntities;
}
