import 'dart:collection';

import 'package:meta/meta.dart';

import '../archetypes/entity_migration_tools/entity_migration_tools.dart';
import '../ecsly.dart';

@immutable
class CommandExecutionFailure {
  const CommandExecutionFailure({
    required this.commandType,
    required this.error,
    required this.stackTrace,
  });

  final Type commandType;
  final Object error;
  final StackTrace stackTrace;
}

class CommandQueue {
  CommandQueue({required this.world});
  final World world;

  final Queue<EcsCommand> _pendingCommands = Queue<EcsCommand>();
  final Queue<CommandExecutionFailure> _failures =
      Queue<CommandExecutionFailure>();

  /// Get the number of pending commands in the queue.
  int get commandCount => _pendingCommands.length;

  bool get needsFlush => _pendingCommands.isNotEmpty;

  /// Deterministic command failures observed during execution.
  ///
  /// Failures are recorded before being rethrown to the caller.
  List<CommandExecutionFailure> get failures => List.unmodifiable(_failures);

  bool get hasFailures => _failures.isNotEmpty;

  void clearFailures() => _failures.clear();

  List<CommandExecutionFailure> drainFailures() {
    final drained = List<CommandExecutionFailure>.from(_failures);
    _failures.clear();
    return drained;
  }

  /// Batch add extension components to multiple entities (zero-initialized).
  ///
  /// Groups entities by current archetype and processes them efficiently.
  /// Extension components are initialized to zero values.
  void batchAddExtensionComponents(
    final List<Entity> entities,
    final List<(Type, Type)> extensionComponents,
  ) {
    if (entities.isEmpty || extensionComponents.isEmpty) return;

    // Create bundle for extension components (zero-initialized)
    final bundle = ComponentBundle.fromExtensionList(extensionComponents);

    // Use unified bundle-first component addition
    _addComponentsToEntitiesUnified(entities: entities, bundle: bundle);
  }

  /// Clear all pending commands without executing them.
  ///
  /// Used when resetting the world state. Pending commands are discarded.
  void clear() {
    _pendingCommands.clear();
    _failures.clear();
  }

  void execute() {
    // Drain in-place to avoid cloning the full queue each flush.
    world.beginStructuralRevisionBatch();
    try {
      while (_pendingCommands.isNotEmpty) {
        final command = _pendingCommands.removeFirst();
        try {
          switch (command) {
            case SpawnEntityComponentsCommand(:final bundle, :final entity):
              _spawnEntityWithComponents(entity, bundle);

            case BatchSpawnCommand(:final bundle, :final count):
              _batchSpawnEntities(bundle, count);

            case DestroyEntityCommand(:final entity):
              _executeDestroyEntities(entity);

            case BatchDestroyEntitiesCommand(:final entities):
              _destroyEntities(entities);

            case UpsertComponentCommand(:final component, :final entity):
              _executeHomogeneousUpserts(entity, component);

            case RemoveComponentCommand(:final entity, :final componentId):
              _removeComponent(entity, componentId);

            case UpsertResourceCommand(:final resource):
              // Resources are handled via ResourceRegistry's queue system
              world.resources.push(resource);

            case DeleteResourceCommand(:final resource):
              // Resources are handled via ResourceRegistry's queue system
              world.resources.removeByType(resource.runtimeType);

            case BatchAddExtensionComponentsCommand(
              :final entities,
              :final extensionComponents,
            ):
              batchAddExtensionComponents(entities, extensionComponents);

            case BatchRemoveComponentsCommand(
              :final entities,
              :final componentIds,
            ):
              _batchRemoveComponents(entities, componentIds);

            case BatchAddClassComponentsCommand(
              :final entities,
              :final components,
            ):
              _batchAddClassComponents(entities, components);
          }
        } on Object catch (error, stackTrace) {
          _failures.addLast(
            CommandExecutionFailure(
              commandType: command.runtimeType,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          rethrow;
        }
      }
    } finally {
      world.endStructuralRevisionBatch();
    }
  }

  /// Pushes a command onto the queue for deferred execution.
  void push(final EcsCommand command) => _pendingCommands.addLast(command);

  /// Unified method for adding components to entities (single or batch).
  ///
  /// This is the core batch-first implementation that handles component addition
  /// efficiently for both single entities and large batches. All component
  /// addition operations should use this method for consistency and performance.
  ///
  /// [entities] - List of entities to add components to
  /// [componentIds] - All component IDs to add (class + extension)
  /// [extensionComponentIds] - Extension component IDs (subset of componentIds)
  /// [bundle] - Optional bundle for class component data (null for extension-only)
  void _addComponentsToEntities({
    required final List<Entity> entities,
    required final List<ComponentId> componentIds,
    required final List<ComponentId> extensionComponentIds,
    final ComponentBundle? bundle,
  }) {
    if (entities.isEmpty || componentIds.isEmpty) return;

    // Single archetype resolution for all entities (batch optimization)
    final archetype = _createArchetypeForComponents(componentIds);
    final archetypeId = archetype.archetypeId;

    // Batch entity addition - most expensive operation, do once for all entities
    final startRow = archetype.addEntities(entities);

    // Batch location setting
    for (var i = 0; i < entities.length; i++) {
      world.entities.setLocation(
        entities[i],
        EntityLocation(archetypeId, startRow + i),
      );
    }

    // Handle class components if bundle provided
    if (bundle != null) {
      final classComponentIds = componentIds
          .where((final id) => !extensionComponentIds.contains(id))
          .toList();
      final rowIndices = List<int>.generate(
        entities.length,
        (final i) => startRow + i,
        growable: false,
      );
      _batchWriteClassComponents(
        archetype,
        bundle,
        classComponentIds,
        rowIndices,
      );
    }
    _initializeExtensionColumns(archetype, extensionComponentIds);

    // Single cache eviction pass for all components
    componentIds.forEach(world.queryCache.evictForStructuralComponent);
    world.recordStructuralChanged();
  }

  /// Unified bundle-first component addition method.
  ///
  /// This is the core implementation that handles all component addition scenarios:
  /// - Fresh entities (no existing components) → Direct addition path
  /// - Entities with existing components → Migration path
  /// - Single entities or large batches → Same optimized logic
  ///
  /// Always initializes extension component facades after archetype operations.
  /// Used as the foundation for all component addition operations.
  void _addComponentsToEntitiesUnified({
    required final List<Entity> entities,
    required final ComponentBundle bundle,
  }) {
    if (entities.isEmpty) return;
    _assertNoAliasingBatchClassWrite(
      operation: '_addComponentsToEntitiesUnified',
      bundle: bundle,
      entityCount: entities.length,
    );

    // Extract component IDs from bundle
    final (
      all: allComponentIds,
      classIds: classComponentIds,
      extensionIds: extensionComponentIds,
    ) = _extractComponentIdsFromBundle(
      bundle,
    );

    if (allComponentIds.isEmpty) return;

    // Group entities by whether they have existing components
    final freshEntities = <Entity>[];
    final entitiesWithComponents = <Entity>[];

    for (final entity in entities) {
      // Validate entity is alive
      if (!world.entities.isAlive(entity)) {
        throw EntityNotFoundError(entity);
      }

      // Check if entity has existing components
      final oldArchetype = ArchetypeResolver.resolveArchetype(
        world.entities,
        world.archetypes,
        entity,
      );

      final hasExistingComponents =
          oldArchetype != null &&
          oldArchetype.contains(entity, world.entities) &&
          oldArchetype.archetypeId != ArchetypeId.zero; // Not empty archetype

      if (hasExistingComponents) {
        entitiesWithComponents.add(entity);
      } else {
        freshEntities.add(entity);
      }
    }

    // Handle fresh entities (direct addition path)
    if (freshEntities.isNotEmpty) {
      _addComponentsToEntities(
        entities: freshEntities,
        componentIds: allComponentIds,
        extensionComponentIds: extensionComponentIds,
        bundle: bundle,
      );
    }

    // Handle entities with existing components (migration path)
    if (entitiesWithComponents.isNotEmpty) {
      _addComponentsToEntitiesViaMigration(
        entities: entitiesWithComponents,
        componentIds: allComponentIds,
        extensionComponentIds: extensionComponentIds,
        bundle: bundle,
      );
    }
  }

  /// Add components to entities that already have existing components (migration path).
  ///
  /// Used when entities already have components and need to be migrated to a new archetype
  /// that includes the additional components.
  void _addComponentsToEntitiesViaMigration({
    required final List<Entity> entities,
    required final List<ComponentId> componentIds,
    required final List<ComponentId> extensionComponentIds,
    required final ComponentBundle bundle,
  }) {
    final classComponentIds = componentIds
        .where((final id) => !extensionComponentIds.contains(id))
        .toList();

    final migrationBatches = <_MigrationBatchKey, List<Entity>>{};
    final computedBySource = <Archetype, ArchetypeSignature>{};
    for (final entity in entities) {
      final oldArchetype = ArchetypeResolver.resolveArchetype(
        world.entities,
        world.archetypes,
        entity,
      )!;
      final newSignature = computedBySource.putIfAbsent(
        oldArchetype,
        () => SignatureComputer.computeAddSignatureMultiple(
          oldArchetype,
          componentIds,
        ),
      );
      final key = _MigrationBatchKey(oldArchetype, newSignature);
      migrationBatches.putIfAbsent(key, () => []).add(entity);
    }

    for (final entry in migrationBatches.entries) {
      final key = entry.key;
      final batchEntities = entry.value;
      final oldArchetype = key.source;
      final needsMigration = key.target != oldArchetype.signature;
      final newArchetype = needsMigration
          ? ArchetypeResolver.resolveDestinationArchetype(
              world.archetypes,
              key.target,
            )
          : oldArchetype;

      final migratedStartRow = needsMigration
          ? EntityMigrator.migrateEntities(
              batchEntities,
              oldArchetype,
              newArchetype,
              const [],
              world.entities,
            )
          : null;
      for (
        var entityIndex = 0;
        entityIndex < batchEntities.length;
        entityIndex++
      ) {
        final entity = batchEntities[entityIndex];
        if (bundle.components.items.isNotEmpty) {
          final rowIndex = needsMigration
              ? migratedStartRow! + entityIndex
              : world.entities.getLocation(entity).archetypeRow;
          for (var i = 0; i < bundle.components.items.length; i++) {
            final componentId = classComponentIds[i];
            final (_, component) = bundle.components.items[i];
            final column = newArchetype.getColumn(componentId);
            if (column != null) {
              ComponentDataWriter.writeToColumn(column, rowIndex, component);
            }
          }
        }
      }

      _initializeExtensionColumns(newArchetype, extensionComponentIds);
    }

    // Batch structural cache eviction for all components
    componentIds.forEach(world.queryCache.evictForStructuralComponent);
    world.recordStructuralChanged();
  }

  /// Batch add class components with data to multiple entities.
  ///
  /// Processes entities in groups and writes component data efficiently.
  void _batchAddClassComponents(
    final List<Entity> entities,
    final List<Component> components,
  ) {
    if (entities.isEmpty || components.isEmpty) return;

    // Create bundle from components
    final bundle = ComponentBundle.fromLists(components);
    _assertNoAliasingBatchClassWrite(
      operation: '_batchAddClassComponents',
      bundle: bundle,
      entityCount: entities.length,
    );

    // Use unified bundle-first component addition
    _addComponentsToEntitiesUnified(entities: entities, bundle: bundle);
  }

  /// Batch remove components from multiple entities with archetype grouping optimization.
  ///
  /// Groups entities by current archetype signature and processes removals
  /// in batch within each archetype group for maximum efficiency.
  void _batchRemoveComponents(
    final List<Entity> entities,
    final List<ComponentId> componentIds,
  ) {
    if (entities.isEmpty || componentIds.isEmpty) return;

    // Group entities by current archetype
    final archetypeGroups = <Archetype, List<Entity>>{};
    for (final entity in entities) {
      if (!world.entities.isAlive(entity)) continue;

      final archetype = ArchetypeResolver.resolveArchetype(
        world.entities,
        world.archetypes,
        entity,
      );
      if (archetype == null) continue;

      archetypeGroups.putIfAbsent(archetype, () => []).add(entity);
    }

    // Process each archetype group
    for (final MapEntry(key: archetype, value: groupEntities)
        in archetypeGroups.entries) {
      _batchRemoveComponentsFromArchetype(
        archetype,
        groupEntities,
        componentIds,
      );
    }

    // Batch structural cache eviction for all removed components
    componentIds.forEach(world.queryCache.evictForStructuralComponent);
    world.recordStructuralChanged();
  }

  /// Batch remove components from entities within the same archetype.
  ///
  /// Computes the new signature once for the archetype group and migrates
  /// all entities in the group together for maximum efficiency.
  void _batchRemoveComponentsFromArchetype(
    final Archetype oldArchetype,
    final List<Entity> entities,
    final List<ComponentId> componentIds,
  ) {
    // Filter component IDs that actually exist in this archetype
    final existingComponentIds = componentIds
        .where(oldArchetype.signature.has)
        .toList();

    if (existingComponentIds.isEmpty) return;

    // Compute new signature (removing all specified components).
    final newSignature = SignatureComputer.computeRemoveSignatureMultiple(
      oldArchetype,
      existingComponentIds,
    );

    // Resolve destination archetype
    final newArchetype = ArchetypeResolver.resolveDestinationArchetype(
      world.archetypes,
      newSignature,
    );

    EntityMigrator.migrateEntities(
      entities,
      oldArchetype,
      newArchetype,
      existingComponentIds,
      world.entities,
    );
  }

  /// Batch spawns multiple entities with the same component bundle efficiently.
  ///
  /// Uses the unified bundle-first component addition method for consistent,
  /// optimized component addition and proper extension component initialization.
  void _batchSpawnEntities(final ComponentBundle bundle, final int count) {
    if (count <= 0) return;
    _assertNoAliasingBatchClassWrite(
      operation: '_batchSpawnEntities',
      bundle: bundle,
      entityCount: count,
    );

    // Extract component IDs from bundle to validate
    final (all: allComponentIds, classIds: _, extensionIds: _) =
        _extractComponentIdsFromBundle(bundle);

    // Validate we have components to spawn
    if (allComponentIds.isEmpty) {
      throw ArgumentError('Cannot batch spawn entities with no components');
    }

    // Pre-allocate entity IDs in batch for better performance
    final entities = List<Entity>.generate(
      count,
      (_) => world.entities.create(),
    );

    // Use unified bundle-first component addition (handles all scenarios)
    _addComponentsToEntitiesUnified(entities: entities, bundle: bundle);
  }

  /// Batch write class-based component data to all entities in the batch.
  ///
  /// Class components require heap allocation and data copying for each entity.
  void _batchWriteClassComponents(
    final Archetype archetype,
    final ComponentBundle bundle,
    final List<ComponentId> classComponentIds,
    final List<int> rowIndices,
  ) {
    if (rowIndices.length > 1 && bundle.components.items.isNotEmpty) {
      throw EcsStateError(
        'Batch write for class components is disallowed in hot paths because '
        'it aliases the same component instance across entities. '
        'Use per-entity writes or extension/SoA components.',
      );
    }
    for (var i = 0; i < bundle.components.items.length; i++) {
      final componentId = classComponentIds[i];
      final (_, component) = bundle.components.items[i];
      final column = archetype.getColumn(componentId);
      if (column == null) {
        throw EcsStateError('Column should exist after archetype creation');
      }

      // Validated above: class component batch writes are single-entity only.
      for (final rowIndex in rowIndices) {
        ComponentDataWriter.writeToColumn(column, rowIndex, component);
      }
    }
  }

  void _executeHomogeneousUpserts(
    final Entity firstEntity,
    final Component firstComponent,
  ) {
    final componentType = firstComponent.runtimeType;
    final componentId = world.components.getComponentIdByType(componentType);
    if (componentId == null) {
      throw ComponentNotRegisteredError(componentType);
    }
    if (!world.entities.isAlive(firstEntity)) {
      throw EntityNotFoundError(firstEntity);
    }

    final firstArchetype = ArchetypeResolver.resolveArchetype(
      world.entities,
      world.archetypes,
      firstEntity,
    );
    if (firstArchetype != null && firstArchetype.signature.has(componentId)) {
      _writeComponent(firstArchetype, firstEntity, componentId, firstComponent);
      return;
    }

    final entities = <Entity>[firstEntity];
    final components = <Component>[firstComponent];
    while (_pendingCommands.isNotEmpty) {
      final next = _pendingCommands.first;
      if (next is! UpsertComponentCommand) break;
      if (next.component.runtimeType != componentType) break;
      _pendingCommands.removeFirst();
      entities.add(next.entity);
      components.add(next.component);
    }

    for (var i = 0; i < entities.length; i++) {
      if (world.entities.isAlive(entities[i])) continue;
      if (i == 0) {
        _restoreUpsertCommands(entities, components, start: 1);
        throw EntityNotFoundError(entities[i]);
      }
      _upsertHomogeneousComponents(
        entities.sublist(0, i),
        componentId,
        components.sublist(0, i),
      );
      _restoreUpsertCommands(entities, components, start: i);
      return;
    }

    _upsertHomogeneousComponents(entities, componentId, components);
  }

  void _writeComponent(
    final Archetype archetype,
    final Entity entity,
    final ComponentId componentId,
    final Component component,
  ) {
    final rowIndex = archetype.getRowIndex(entity, world.entities);
    if (rowIndex == null) return;
    final column = archetype.getColumn(componentId);
    if (column != null) {
      ComponentDataWriter.writeToColumn(column, rowIndex, component);
    }
  }

  void _restoreUpsertCommands(
    final List<Entity> entities,
    final List<Component> components, {
    required final int start,
  }) {
    for (var i = entities.length - 1; i >= start; i--) {
      _pendingCommands.addFirst(
        UpsertComponentCommand(entities[i], components[i]),
      );
    }
  }

  void _upsertHomogeneousComponents(
    final List<Entity> entities,
    final ComponentId componentId,
    final List<Component> components,
  ) {
    final freshEntities = <Entity>[];
    final freshComponents = <Component>[];
    final updateGroups = <Archetype, _ComponentWriteBatch>{};
    final migrationGroups = <_MigrationBatchKey, _ComponentWriteBatch>{};
    final computedBySource = <Archetype, ArchetypeSignature>{};

    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      if (!world.entities.isAlive(entity)) {
        throw EntityNotFoundError(entity);
      }

      final component = components[i];
      final oldArchetype = ArchetypeResolver.resolveArchetype(
        world.entities,
        world.archetypes,
        entity,
      );
      if (oldArchetype == null) {
        freshEntities.add(entity);
        freshComponents.add(component);
        continue;
      }

      if (oldArchetype.signature.has(componentId)) {
        final batch = updateGroups.putIfAbsent(
          oldArchetype,
          _ComponentWriteBatch.new,
        );
        batch.entities.add(entity);
        batch.components.add(component);
        continue;
      }

      final newSignature = computedBySource.putIfAbsent(
        oldArchetype,
        () => SignatureComputer.computeAddSignature(oldArchetype, componentId),
      );
      final key = _MigrationBatchKey(oldArchetype, newSignature);
      final batch = migrationGroups.putIfAbsent(key, _ComponentWriteBatch.new);
      batch.entities.add(entity);
      batch.components.add(component);
    }

    if (freshEntities.isNotEmpty) {
      final archetype = _createArchetypeForComponents([componentId]);
      final startRow = archetype.addEntities(freshEntities);
      final archetypeId = archetype.archetypeId;
      final column = archetype.getColumn(componentId);
      if (column == null) {
        throw EcsStateError('Column should exist after archetype creation');
      }
      for (var i = 0; i < freshEntities.length; i++) {
        world.entities.setLocation(
          freshEntities[i],
          EntityLocation(archetypeId, startRow + i),
        );
        ComponentDataWriter.writeToColumn(
          column,
          startRow + i,
          freshComponents[i],
        );
      }
      world.queryCache.evictForStructuralComponent(componentId);
      world.recordStructuralChanged();
    }

    for (final entry in updateGroups.entries) {
      final archetype = entry.key;
      final batch = entry.value;
      final column = archetype.getColumn(componentId);
      if (column == null) continue;
      for (var i = 0; i < batch.entities.length; i++) {
        final rowIndex = world.entities
            .getLocation(batch.entities[i])
            .archetypeRow;
        ComponentDataWriter.writeToColumn(
          column,
          rowIndex,
          batch.components[i],
        );
      }
    }

    for (final entry in migrationGroups.entries) {
      final key = entry.key;
      final batch = entry.value;
      final newArchetype = ArchetypeResolver.resolveDestinationArchetype(
        world.archetypes,
        key.target,
      );
      final startRow = EntityMigrator.migrateEntities(
        batch.entities,
        key.source,
        newArchetype,
        const [],
        world.entities,
      );
      if (startRow == null) continue;
      final column = newArchetype.getColumn(componentId);
      if (column != null) {
        for (var i = 0; i < batch.entities.length; i++) {
          ComponentDataWriter.writeToColumn(
            column,
            startRow + i,
            batch.components[i],
          );
        }
      }
    }
    if (migrationGroups.isNotEmpty) {
      world.queryCache.evictForStructuralComponent(componentId);
      world.recordStructuralChanged();
    }
  }

  /// Create or get archetype for the given component IDs.
  ///
  /// Returns the archetype instance.
  Archetype _createArchetypeForComponents(
    final List<ComponentId> componentIds,
  ) {
    final signature = ArchetypeSignature.fromIds(componentIds);
    final archetypeId = world.archetypes.getOrCreateArchetype(signature);
    final archetypeIndex = world.archetypes.findArchetypeIndex(archetypeId);
    return world.archetypes[archetypeIndex];
  }

  /// Destroys an entity and removes it from its archetype.
  void _executeDestroyEntities(final Entity firstEntity) {
    var changed = _destroyEntity(firstEntity);
    while (_pendingCommands.isNotEmpty) {
      final next = _pendingCommands.first;
      if (next is! DestroyEntityCommand) break;
      _pendingCommands.removeFirst();
      changed = _destroyEntity(next.entity) || changed;
    }
    if (changed) {
      world.recordStructuralChanged();
    }
  }

  void _destroyEntities(final List<Entity> entities) {
    var changed = false;
    for (final entity in entities) {
      changed = _destroyEntity(entity) || changed;
    }
    if (changed) {
      world.recordStructuralChanged();
    }
  }

  bool _destroyEntity(final Entity entity) {
    if (!world.entities.isAlive(entity)) return false;

    // Get location and archetype
    final location = world.entities.getLocation(entity);
    final archetypeIndex = world.archetypes.findArchetypeIndex(
      location.archetypeId,
    );
    final archetype = world.archetypes[archetypeIndex];

    // Remove from archetype (which also invalidates the entity's row)
    archetype.removeEntity(entity, world.entities);

    // Now, officially destroy and recycle the entity ID
    world.entities.destroy(entity);
    return true;
  }

  /// Extract component IDs from a component bundle.
  ///
  /// Returns a record containing all component IDs, class component IDs, and extension component IDs.
  ({
    List<ComponentId> all,
    List<ComponentId> classIds,
    List<ComponentId> extensionIds,
  })
  _extractComponentIdsFromBundle(final ComponentBundle bundle) {
    final allComponentIds = <ComponentId>[];
    final classComponentIds = <ComponentId>[];
    final extensionComponentIds = <ComponentId>[];

    // Add class-based component IDs
    for (final (type, _) in bundle.components.items) {
      final componentId = world.components.getComponentIdByType(type);
      if (componentId == null) {
        throw ComponentNotRegisteredError(type);
      }
      classComponentIds.add(componentId);
      allComponentIds.add(componentId);
    }

    // Add extension-based component IDs
    for (final (componentType, _) in bundle.extensionComponents.items) {
      final componentId = world.components.getComponentIdByType(componentType);
      if (componentId == null) {
        throw ComponentNotRegisteredError(componentType);
      }
      extensionComponentIds.add(componentId);
      allComponentIds.add(componentId);
    }

    return (
      all: allComponentIds,
      classIds: classComponentIds,
      extensionIds: extensionComponentIds,
    );
  }

  /// Batch-optimized extension component initialization.
  ///
  /// Initializes facade factories for multiple extension components efficiently,
  /// with proper error handling and validation. Used by the unified
  /// component addition system.
  void _initializeExtensionColumns(
    final Archetype archetype,
    final List<ComponentId> extensionComponentIds,
  ) {
    if (extensionComponentIds.isEmpty) return;

    for (final componentId in extensionComponentIds) {
      final column = archetype.getColumn(componentId);
      if (column == null) {
        throw EcsStateError(
          'Extension component column missing from archetype: $componentId. '
          'Archetype ID: ${archetype.archetypeId}',
        );
      }

      // Batch-optimized facade factory initialization
      world.components.componentFacadeRegistry.initializeColumn(
        componentId,
        column,
      );
    }
  }

  /// Removes a component from an entity.
  ///
  /// Migrates entity to new archetype without the component.
  /// If removing last component, entity migrates to empty archetype.
  void _removeComponent(final Entity entity, final ComponentId componentId) {
    if (!world.entities.isAlive(entity)) return;

    // Resolve current archetype
    final oldArchetype = ArchetypeResolver.resolveArchetype(
      world.entities,
      world.archetypes,
      entity,
    );
    if (oldArchetype == null) return;

    // Check if component exists (if not, skip)
    if (!oldArchetype.signature.has(componentId)) {
      return; // Component not present, nothing to remove
    }

    // Compute new signature (will be empty if removing last component)
    final newSignature = SignatureComputer.computeRemoveSignature(
      oldArchetype,
      componentId,
    );

    // Resolve destination archetype (may be empty archetype)
    final newArchetype = ArchetypeResolver.resolveDestinationArchetype(
      world.archetypes,
      newSignature,
    );

    // Migrate entity excluding the removed component
    EntityMigrator.migrateEntity(
      entity,
      oldArchetype,
      newArchetype,
      componentId, // Exclude this component
      null, // No new component
      null, // No new component data
      world.entities, // Update location
    );

    // Structural cache eviction for removed component
    world.queryCache.evictForStructuralComponent(componentId);
    world.recordStructuralChanged();
  }

  /// Spawns an entity with a bundle of components.
  ///
  /// Uses the unified bundle-first component addition method for consistent,
  /// optimized component addition and proper extension component initialization.
  void _spawnEntityWithComponents(
    final Entity entity,
    final ComponentBundle bundle,
  ) {
    // Validate entity is alive
    if (!world.entities.isAlive(entity)) {
      throw EntityNotFoundError(entity);
    }

    // Use unified bundle-first component addition (handles all scenarios)
    _addComponentsToEntitiesUnified(entities: [entity], bundle: bundle);
  }

  void _assertNoAliasingBatchClassWrite({
    required final String operation,
    required final ComponentBundle bundle,
    required final int entityCount,
  }) {
    if (entityCount <= 1 || bundle.components.items.isEmpty) {
      return;
    }

    final componentTypes = bundle.components.items
        .map((final item) => item.$1.toString())
        .join(', ');
    throw EcsStateError(
      '$operation does not support class component batch writes because the '
      'same instance would be shared across entities. '
      'Use extension/SoA components or perform per-entity insertion with '
      'distinct instances. '
      'Components: [$componentTypes], entityCount=$entityCount.',
    );
  }
}

@immutable
final class _MigrationBatchKey {
  const _MigrationBatchKey(this.source, this.target);

  final Archetype source;
  final ArchetypeSignature target;

  @override
  int get hashCode => Object.hash(source.archetypeId, target);

  @override
  bool operator ==(final Object other) =>
      other is _MigrationBatchKey &&
      source.archetypeId == other.source.archetypeId &&
      target == other.target;
}

final class _ComponentWriteBatch {
  final List<Entity> entities = <Entity>[];
  final List<Component> components = <Component>[];
}
