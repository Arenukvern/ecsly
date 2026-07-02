// ignore_for_file: cascade_invocations

import 'package:meta/meta.dart';

import '../archetypes/archetypes.dart';
import '../commands/commands.dart';
import '../components/components.dart';
import '../entities/entities.dart';
import '../errors/ecs_errors.dart';
import '../resources/resources.dart';
import '../systems/systems.dart';
import 'world.dart';

extension WorldBatchSpawnX on World {
  /// Spawn multiple entities with the same component bundle efficiently.
  ///
  /// This batch operation is optimized for large-scale spawning (100-10000 entities)
  /// and provides significant performance improvements over individual spawn calls.
  ///
  /// The spawning is deferred via the command queue for consistency with other operations.
  ///
  /// Internally dispatches to specialized commands based on component types:
  /// - Extension-based components (Position, Velocity): ultra-fast zero-initialization
  /// - Class-based components (Health, Name): optimized data writing
  ///
  /// Example:
  /// ```dart
  /// // Spawn 10000 particles with the same components
  /// final bundle = ComponentBundle.fromList([
  ///   const Position(0, 0),
  ///   const Velocity(1, 1),
  ///   const Lifetime(5.0),
  /// ], [(LifetimeComponent, Lifetime)]);
  /// world.batchSpawn(bundle, 10000);
  /// ```
  void batchSpawn(final ComponentBundle bundle, final int count) =>
      commands.batchSpawn(bundle, count);

  /// Pre-register archetypes for efficient batch spawning.
  ///
  /// Call this before batch spawning to avoid query cache invalidations
  /// during the spawn process. This is particularly useful when spawning
  /// large numbers of entities with known component combinations.
  ///
  /// Example:
  /// ```dart
  /// // Pre-register archetypes for different entity types
  /// world.preRegisterArchetypesForBundles([
  ///   ComponentBundle.fromList([const Position(), const Velocity()]),
  ///   ComponentBundle.fromList([const Position(), const Health()]),
  /// ]);
  ///
  /// // Now batch spawn without cache invalidations
  /// world.commands.batchSpawn(bundle1, 5000);
  /// world.commands.batchSpawn(bundle2, 5000);
  /// ```
  void preRegisterArchetypesForBundles(final List<ComponentBundle> bundles) {
    final signatures = <ArchetypeSignature>[];
    for (final bundle in bundles) {
      final componentIds = <ComponentId>[];
      for (final (type, _) in bundle.components.items) {
        final componentId = components.getComponentIdByType(type);
        if (componentId != null) {
          componentIds.add(componentId);
        }
      }
      if (componentIds.isNotEmpty) {
        signatures.add(ArchetypeSignature.fromIds(componentIds));
      }
    }
    archetypes.preRegisterArchetypes(signatures);
  }
}

extension WorldComponentX on World {
  /// Get a component of type T for the given entity.
  ///
  /// Validates entity exists before accessing component. Throws [EntityNotFoundError]
  /// if entity is not alive or [ComponentNotFoundError] if component is not found.
  ///
  /// Automatically flushes pending changes before access to ensure data consistency.
  T getComponent<T extends Component>(final Entity entity) {
    ensureFlushed();
    if (!entities.isAlive(entity)) {
      throw EntityNotFoundError(entity);
    }
    final location = entities.getLocation(entity);
    final archetypeIndex = archetypes.findArchetypeIndex(location.archetypeId);
    final archetype = archetypes[archetypeIndex];
    final component = archetype.getComponentByEntity<T>(
      entity,
      components,
      entities,
    );
    if (component == null) {
      throw ComponentNotFoundError(T, entity);
    }
    return component;
  }

  /// Returns a component for [entity] without throwing.
  ///
  /// This is a direct entity lookup. It does not scan archetypes and does not
  /// allocate an entity/component pair. Domain ids should be modeled as normal
  /// components; any app-level id lookup belongs in host/plugin infrastructure.
  T? maybeGetComponent<T extends Component>(final Entity entity) {
    ensureFlushed();

    if (!entities.isAlive(entity)) return null;
    final location = entities.getLocation(entity);
    if (location.archetypeId == ArchetypeId.zero) return null;
    final archetypeIndex = archetypes.findArchetypeIndex(location.archetypeId);
    final archetype = archetypes[archetypeIndex];
    final component = archetype.getComponentByIndex<T>(
      location.archetypeRow,
      components,
    );
    if (component == null) return null;
    return component;
  }

  /// Remove a component of type T from the given entity.
  ///
  /// Returns [EntityCommands] for method chaining. The removal is deferred
  /// via the command queue and will be processed on the next flush.
  EntityCommands removeComponent<T extends Component>(final Entity entity) {
    final commands = EntityCommands(queue: commandQueue, entity: entity);
    commands.remove<T>();
    return commands;
  }

  /// Spawn an entity with a bundle of components atomically.
  ///
  /// More efficient than multiple upsert calls as it processes
  /// all components together in a single archetype resolution.
  ///
  /// The entity must already exist (use [reserveEmptyEntity] first).
  /// Component addition is deferred via the command queue.
  EntityCommands spawnBundle(
    final Entity entity,
    final ComponentBundle bundle,
  ) => commands.spawnBundle(entity, bundle);

  /// Upsert (insert or update) a component of type T for the given entity.
  ///
  /// If the component exists, it will be updated. If it doesn't exist,
  /// it will be added (causing entity migration to a new archetype).
  ///
  /// Returns [EntityCommands] for method chaining. The change is deferred
  /// via the command queue and will be processed on the next flush.
  EntityCommands upsertComponent<T extends Component>(
    final Entity entity,
    final T component,
  ) {
    final commands = EntityCommands(queue: commandQueue, entity: entity);
    commands.upsert<T>(component);
    return commands;
  }
}

/// Entity management extensions for World.
///
/// Provides convenient methods for entity lifecycle management.
extension WorldEntityX on World {
  /// Reserve an entity and spawn it with [bundle], returning the entity id.
  ///
  /// This is a cold-path convenience around [reserveEmptyEntity] and
  /// [spawnBundle]. The structural write is still deferred until flush.
  Entity spawnComponentBundle(final ComponentBundle bundle) {
    final entity = reserveEmptyEntity().entity;
    spawnBundle(entity, bundle);
    return entity;
  }

  /// Reserve an entity and spawn it with one component bundle built from lists.
  Entity spawnComponents(
    final List<Component> components, [
    final List<(Type, Type)> extensionComponents = const [],
  ]) => spawnComponentBundle(
    ComponentBundle.fromLists(components, extensionComponents),
  );

  /// Despawn an entity, removing it from the world.
  ///
  /// Uses the command queue to defer the despawn operation, ensuring
  /// safe removal during iteration. The entity and all its components
  /// will be removed on the next flush.
  void despawnEntity(final Entity entity) {
    EntityCommands(queue: commandQueue, entity: entity).despawn();
  }

  /// Get a [WorldEntity] wrapper for the given entity.
  ///
  /// Provides Bevy-like API for working with entities in the world.
  /// This wrapper is a convenience/cold-path API; prefer raw query chunk APIs
  /// for hot simulation loops.
  /// Returns isValid=false if entity is not found (does not throw).
  ///
  /// The bool isValid is true if the entity is still valid, false otherwise
  (WorldEntity, bool isValid) getEntity(final Entity entity) {
    ensureFlushed();
    return getEntityFast(entity);
  }

  /// Get a [WorldEntity] wrapper without triggering auto-flush.
  ///
  /// This is a hot-path variant for internal/system usage when the caller
  /// already guarantees a consistent world state (typically after explicit flush
  /// or inside query iterators that flush once before iteration).
  ///
  /// Returns isValid=false if entity is not found (does not throw).
  (WorldEntity, bool isValid) getEntityFast(final Entity entity) {
    final location = entities.getLocation(entity);
    final isValid = entities.isAlive(entity);

    return (
      WorldEntity(world: this, entity: entity, location: location),
      isValid,
    );
  }

  /// Get a [WorldEntityExtension] wrapper for the given entity.
  ///
  /// Provides type-safe access to extension type facades (e.g., Position, Velocity).
  /// This wrapper is a convenience/cold-path API; prefer raw query chunk APIs
  /// for hot simulation loops.
  /// Returns isValid=false if entity is not found (does not throw).
  (WorldEntityExtension, bool isValid) getEntityExtension(final Entity entity) {
    ensureFlushed();
    return getEntityExtensionFast(entity);
  }

  /// Get a [WorldEntityExtension] wrapper without triggering auto-flush.
  ///
  /// Hot-path variant for callers that already ensured flush consistency.
  (WorldEntityExtension, bool isValid) getEntityExtensionFast(
    final Entity entity,
  ) {
    final (baseEntity, isValid) = getEntityFast(entity);
    return (baseEntity.toExtension(), isValid);
  }

  /// Get a [WorldEntityMut] wrapper for the given entity.
  ///
  /// Provides mutable access to entity components for direct in-place mutation.
  /// Similar to Bevy's `&mut Component` pattern.
  /// This wrapper is a convenience/cold-path API; prefer raw query chunk APIs
  /// for hot simulation loops.
  ///
  /// **Key Distinction:**
  /// - **WorldEntityMut**: For data mutation (doesn't change archetype) - direct in-place updates
  /// - **WorldEntity**: For structural changes (spawn/despawn/insert/remove components) - changes archetype
  ///
  /// Returns isValid=false if entity is not found (does not throw).
  (WorldEntityMut, bool isValid) getEntityMut(final Entity entity) {
    ensureFlushed();
    return getEntityMutFast(entity);
  }

  /// Get a [WorldEntityMut] wrapper without triggering auto-flush.
  ///
  /// Hot-path variant for callers that already ensured flush consistency.
  (WorldEntityMut, bool isValid) getEntityMutFast(final Entity entity) {
    final location = entities.getLocation(entity);
    final isValid = entities.isAlive(entity);
    final baseEntity = WorldEntity(
      world: this,
      entity: entity,
      location: location,
    );
    return (WorldEntityMut(baseEntity), isValid);
  }

  EntityCommands reserveEmptyEntity() {
    final entity = entities.create();
    return EntityCommands(queue: commandQueue, entity: entity);
  }

  /// Reserve [count] empty entities and return their ids.
  ///
  /// Use this when a caller needs many entity ids before scheduling structural
  /// commands. Returning raw [Entity] values avoids allocating one
  /// [EntityCommands] wrapper per reserved entity.
  List<Entity> reserveEmptyEntities(final int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<Entity>.generate(count, (_) => entities.create());
  }
}

extension WorldFlushX on World {
  /// Clears all world state, resetting to initial state.
  ///
  /// Clears resources, systems, commands, and query cache.
  /// Entities and components are stored in archetypes and will be cleared
  /// when archetypes are cleared (via systems or manual archetype management).
  /// After calling this, the world is ready for new entities/components.
  void clear() {
    resources.clear();
    systems.clear();
    commandQueue.clear();
    queryCache.clear();
    // Note: Entities and components are managed via archetypes.
    // Clearing archetypes would require iterating all archetypes,
    // which is expensive. Consider clearing specific archetypes if needed.
  }

  /// Conditionally flushes the world if any pending changes exist.
  ///
  /// This method checks if resources or commands have pending changes and only
  /// flushes if needed. This enables efficient auto-flushing at query/access
  /// points without unnecessary overhead.
  ///
  /// Used internally by query access points and component/resource access
  /// methods to ensure data consistency while maintaining performance.
  ///
  /// Following Bevy's design: skips flush if already flushing to prevent
  /// recursive flush-during-flush cycles during command execution.
  @internal
  void ensureFlushed() {
    if (isFlushing) return; // Prevent recursive flushing
    if (resources.doesNeedFlush || commandQueue.needsFlush) {
      flush();
    }
  }

  /// Execute commands from the command queue (conditional - only if needed).
  ///
  /// Commands are deferred structural changes (spawn/despawn, add/remove components).
  /// This method processes all pending commands in the queue.
  void executeCommands() {
    if (commandQueue.needsFlush) {
      commandQueue.execute();
    }
  }

  /// Flush all registries in order: entities → components → resources → commands.
  ///
  /// Order is critical: entities must be ready first, then components and
  /// resources must be flushed before commands execute (commands may need to
  /// access flushed components and resources). Commands execute last to process
  /// any deferred operations.
  ///
  /// After commands execute, a conditional second flush occurs if new pending
  /// changes were created (Bevy-style pattern). This ensures deferred operations
  /// are immediately visible.
  ///
  /// Uses `isFlushing` guard to prevent recursive flush-during-flush cycles.
  void flush() {
    final flushObserver = this.flushObserver;
    final startUs = flushObserver != null
        ? DateTime.now().microsecondsSinceEpoch
        : 0;
    final commandsExecuted = flushObserver != null
        ? commandQueue.commandCount
        : 0;
    final resourcesPushed = flushObserver != null
        ? resources.pendingPushCount
        : 0;
    final resourcesRemoved = flushObserver != null
        ? resources.pendingRemoveCount
        : 0;

    flushObserver?.onFlushStart(this);
    isFlushing = true; // Prevent recursive flush calls
    try {
      flushEntitiesOnly();
      flushComponentsOnly();
      flushResourcesOnly();
      flushCommandsOnly(); // Commands after components and resources are flushed

      // Bevy-style: Flush again after commands to make deferred ops visible
      // Commands may have pushed to pending queues, so flush them now
      if (resources.doesNeedFlush) {
        flushResourcesOnly();
      }

      // Notify query cache of world flush
      queryCache.onWorldFlush();
    } finally {
      isFlushing = false; // Always reset flag, even on exceptions
      if (flushObserver != null) {
        final elapsedUs = DateTime.now().microsecondsSinceEpoch - startUs;
        flushObserver.onFlushEnd(
          this,
          elapsedMicroseconds: elapsedUs,
          commandsExecuted: commandsExecuted,
          resourcesPushed: resourcesPushed,
          resourcesRemoved: resourcesRemoved,
        );
      }
    }
  }

  /// Execute only commands (conditional - only if needed).
  ///
  /// Processes all pending commands in the command queue. Used by phase systems
  /// for fine-grained control over flush order.
  void flushCommandsOnly() {
    if (commandQueue.needsFlush) {
      commandQueue.execute();
    }
  }

  /// Flush only components (conditional - only if needed).
  ///
  /// Note: Components are stored in archetypes and don't have a pending queue.
  /// Component changes are processed via the command queue. This method is
  /// kept for API consistency with phase systems but is a no-op.
  void flushComponentsOnly() {
    // Components are stored in archetypes, no pending queue to flush
    // Component changes are processed via command queue execution
  }

  /// Flush only entities (conditional - only if needed).
  ///
  /// Note: Entities don't have a pending queue - they're managed directly.
  /// Entity changes are processed via the command queue. This method is
  /// kept for API consistency with phase systems but is a no-op.
  void flushEntitiesOnly() {
    // Entities don't have a pending queue - they're managed directly
    // Entity changes are processed via command queue execution
  }

  /// Flush only resources (conditional - only if needed).
  ///
  /// Processes pending resource changes (additions/removals). Used by phase
  /// systems for fine-grained control over flush order.
  void flushResourcesOnly() {
    if (resources.doesNeedFlush) resources.flush();
  }
}

extension WorldPluginX on World {
  /// Add a plugin to this world.
  ///
  /// Throws [PluginInstallationException] if a plugin with the same name is already installed.
  void addPlugin(final Plugin plugin) {
    flush();
    systems.plugins.add(plugin, this);
  }

  /// Add [plugin] only when a plugin with the same name is not installed.
  ///
  /// Returns true when the plugin was installed, false when it was already
  /// present. This does not replace existing plugins; use [removePlugin]
  /// followed by [addPlugin] when replacement/uninstall semantics are needed.
  bool addPluginIfAbsent(final Plugin plugin) {
    if (hasPlugin(plugin.name)) return false;
    addPlugin(plugin);
    return true;
  }

  /// Get a plugin by name.
  Plugin? getPlugin(final String name) => systems.plugins.get(name);

  /// Check if a plugin is installed.
  bool hasPlugin(final String name) => systems.plugins.has(name);

  /// Remove a plugin from this world.
  ///
  /// Returns true if a plugin was removed, false otherwise.
  bool removePlugin(final String name) {
    flush();
    return systems.plugins.remove(name, this);
  }
}

extension WorldResourceX on World {
  T getResource<T extends Resource>() => resources.get<T>();
  T? maybeGetResource<T extends Resource>() =>
      resources.has<T>() ? resources.get<T>() : null;

  T? getResourceById<T extends Resource>(final ResourceId id) =>
      resources.getById<T>(id);

  /// Remove a resource of type T from the world.
  ///
  /// The removal is deferred via the resource registry's pending queue
  /// and will be processed on the next flush.
  void removeResource<T extends Resource>() {
    flushResourcesOnly();
    resources.remove<T>();
  }

  /// Upsert (insert or update) a resource of type T in the world.
  ///
  /// Resources are global singletons. Only one instance of each type can exist.
  /// The change is deferred via the resource registry's pending queue
  /// and will be processed on the next flush.
  void upsertResource<T extends Resource>(final T resource) {
    flushResourcesOnly();
    resources.push(resource);
  }

  /// Add a resource created by [create] only when [T] is absent.
  ///
  /// Returns the existing resource when present, otherwise creates, stores, and
  /// returns a new resource. This is a cold-path setup helper; app/UI
  /// invalidation should remain in app-layer action APIs.
  T addResourceIfAbsent<T extends Resource>(final T Function() create) {
    if (resources.has<T>()) return resources.get<T>();
    final resource = create();
    upsertResource(resource);
    return resource;
  }
}

extension WorldScheduleX on World {
  /// Create a new schedule with optional trigger.
  ///
  /// Throws [EcsStateError] if a schedule with the same name already exists.
  Schedule createSchedule(
    final String name, {
    final ScheduleTrigger? trigger,
  }) => systems.createSchedule(name, trigger: trigger);

  /// Get or create a schedule.
  Schedule getOrCreateSchedule(
    final String name, {
    final ScheduleTrigger? trigger,
  }) => systems.getOrCreateSchedule(name, trigger: trigger);

  /// Check if a schedule exists.
  bool hasSchedule(final String name) => systems.hasSchedule(name);

  /// Remove a schedule by name.
  bool removeSchedule(final String name) => systems.removeSchedule(name);

  /// Run a schedule by name (synchronously).
  ///
  /// If the schedule has a trigger, it will only execute if the trigger
  /// condition is met.
  void runSchedule(final String name) => schedule(name).run(this);

  /// Run a schedule by name (asynchronously).
  Future<void> runScheduleAsync(final String name) =>
      schedule(name).runAsync(this);

  /// Run a system directly (for input layer or one-off execution).
  void runSystem(final System system) => system(this);

  /// Run an async system directly.
  Future<void> runSystemAsync(final AsyncSystem system) => system(this);

  /// Get a schedule by name.
  ///
  /// Throws [EcsStateError] if the schedule doesn't exist.
  Schedule schedule(final String name) => systems.getSchedule(name);
}
