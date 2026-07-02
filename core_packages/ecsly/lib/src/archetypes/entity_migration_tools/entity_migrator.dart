// ignore_for_file: avoid_annotating_with_dynamic

import '../../components/component.dart';
import '../../entities/entities.dart';
import '../archetype.dart';
import 'component_data_integrator.dart';

/// Core migration execution logic.
///
/// Handles the unified migration of entities between archetypes, including
/// component copying, new component writing, and location updates.
class EntityMigrator {
  EntityMigrator._();

  /// Migrates an entity from source archetype to destination archetype.
  ///
  /// [entity] - The entity to migrate
  /// [sourceArchetype] - The source archetype (entity currently in)
  /// [destArchetype] - The destination archetype (entity will be moved to)
  /// [excludeComponentId] - Optional component ID to exclude from copying (for removal)
  /// [newComponentId] - Optional component ID being added
  /// [newComponentData] - Optional component data for the new component
  /// [entities] - Optional Entities manager to update location (if null, location not updated)
  ///
  /// Returns the new row index in the destination archetype, or null if migration failed.
  static int? migrateEntity(
    final Entity entity,
    final Archetype sourceArchetype,
    final Archetype destArchetype,
    final ComponentId? excludeComponentId,
    final ComponentId? newComponentId,
    final dynamic newComponentData,
    final Entities? entities,
  ) {
    // Entities manager is required for migration (needed for location tracking)
    if (entities == null) return null;

    // 1. Get source row index from global location tracking
    final sourceLocation = entities.getLocation(entity);
    if (sourceLocation.archetypeId != sourceArchetype.archetypeId) {
      // Entity is not in source archetype - migration invalid
      return null;
    }
    final sourceRowIndex = sourceLocation.archetypeRow;

    // 2. Add entity to destination (gets new row index)
    final destRowIndex = destArchetype.addEntity(entity);

    // 3. Copy all shared components from source to destination
    for (final componentId in sourceArchetype.componentIds) {
      // Skip if this component is being excluded (removed)
      if (componentId == excludeComponentId) {
        continue;
      }

      final sourceColumn = sourceArchetype.getColumn(componentId);
      final destColumn = destArchetype.getColumn(componentId);

      if (sourceColumn != null && destColumn != null) {
        // Copy component data using Column abstraction
        sourceColumn.copyTo(sourceRowIndex, destColumn, destRowIndex);
      }
    }

    // 4. Set new component data if adding
    if (newComponentId != null && newComponentData != null) {
      final destColumn = destArchetype.getColumn(newComponentId);
      if (destColumn != null) {
        ComponentDataIntegrator.writeComponentData(
          destColumn,
          destRowIndex,
          newComponentData,
        );
      }
    }

    // 5. Remove entity from source archetype (updates location tracking via swap-pop)
    sourceArchetype.removeEntity(entity, entities);

    // 6. Update entity location to destination archetype
    final newArchetypeId = destArchetype.archetypeId;
    entities.setLocation(entity, EntityLocation(newArchetypeId, destRowIndex));

    return destRowIndex;
  }

  /// Migrates a homogeneous source-archetype batch into [destArchetype].
  ///
  /// Returns the first destination row. Destination rows are contiguous and map
  /// to [entities] by index (`firstRow + i`). Source removals still use
  /// [Archetype.removeEntity], preserving the existing swap-pop location logic.
  static int? migrateEntities(
    final List<Entity> entities,
    final Archetype sourceArchetype,
    final Archetype destArchetype,
    final List<ComponentId> excludeComponentIds,
    final Entities entitiesManager,
  ) {
    if (entities.isEmpty) return null;
    if (identical(sourceArchetype, destArchetype)) {
      return entitiesManager.getLocation(entities.first).archetypeRow;
    }

    final sourceRows = List<int>.filled(entities.length, 0);
    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      final sourceLocation = entitiesManager.getLocation(entity);
      if (sourceLocation.archetypeId != sourceArchetype.archetypeId) {
        return null;
      }
      sourceRows[i] = sourceLocation.archetypeRow;
    }

    final destStartRow = destArchetype.addEntities(entities);
    for (final componentId in sourceArchetype.componentIds) {
      if (_containsComponentId(excludeComponentIds, componentId)) {
        continue;
      }

      final sourceColumn = sourceArchetype.getColumn(componentId);
      final destColumn = destArchetype.getColumn(componentId);
      if (sourceColumn == null || destColumn == null) {
        continue;
      }

      for (var i = 0; i < entities.length; i++) {
        sourceColumn.copyTo(sourceRows[i], destColumn, destStartRow + i);
      }
    }

    for (final entity in entities) {
      sourceArchetype.removeEntity(entity, entitiesManager);
    }

    final newArchetypeId = destArchetype.archetypeId;
    for (var i = 0; i < entities.length; i++) {
      entitiesManager.setLocation(
        entities[i],
        EntityLocation(newArchetypeId, destStartRow + i),
      );
    }

    return destStartRow;
  }
}

bool _containsComponentId(
  final List<ComponentId> componentIds,
  final ComponentId componentId,
) {
  for (final id in componentIds) {
    if (id == componentId) return true;
  }
  return false;
}
