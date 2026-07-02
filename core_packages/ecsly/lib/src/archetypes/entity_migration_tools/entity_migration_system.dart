// ignore_for_file: avoid_annotating_with_dynamic

import '../../components/component.dart';
import '../../entities/entities.dart';
import '../archetypes_registry.dart';
import 'entity_migration_tools.dart';

/// Handles entity migration between archetypes when components are added/removed.
///
/// Orchestrates migration using reusable migration tools for clear separation
/// of concerns and improved maintainability.
class EntityMigrationSystem {
  EntityMigrationSystem(this._archetypeRegistry, this._entities);

  final ArchetypeRegistry _archetypeRegistry;
  final Entities _entities;

  /// Migrate entity to new archetype (add component)
  void migrateAddComponent(
    final Entity entity,
    final ComponentId newComponentId,
    final dynamic componentData,
  ) {
    // 1. Resolve current archetype
    final currentArchetype = ArchetypeResolver.resolveArchetype(
      _entities,
      _archetypeRegistry,
      entity,
    );
    if (currentArchetype == null) return;

    // 2. Compute new signature
    final newSignature = SignatureComputer.computeAddSignature(
      currentArchetype,
      newComponentId,
    );

    // 3. Resolve destination archetype
    final destArchetype = ArchetypeResolver.resolveDestinationArchetype(
      _archetypeRegistry,
      newSignature,
    );

    // 4. Migrate entity
    EntityMigrator.migrateEntity(
      entity,
      currentArchetype,
      destArchetype,
      null, // No component excluded
      newComponentId,
      componentData,
      _entities, // Update location
    );
  }

  /// Migrate entity to new archetype (remove component)
  void migrateRemoveComponent(
    final Entity entity,
    final ComponentId componentId,
  ) {
    // 1. Resolve current archetype
    final currentArchetype = ArchetypeResolver.resolveArchetype(
      _entities,
      _archetypeRegistry,
      entity,
    );
    if (currentArchetype == null) return;

    // 2. Compute new signature
    final newSignature = SignatureComputer.computeRemoveSignature(
      currentArchetype,
      componentId,
    );

    // 3. Resolve destination archetype
    final destArchetype = ArchetypeResolver.resolveDestinationArchetype(
      _archetypeRegistry,
      newSignature,
    );

    // 4. Migrate entity (excluding the removed component)
    EntityMigrator.migrateEntity(
      entity,
      currentArchetype,
      destArchetype,
      componentId, // Exclude this component
      null, // No new component
      null, // No new component data
      _entities, // Update location
    );
  }
}
