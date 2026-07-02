import 'package:meta/meta.dart';

import '../archetypes/archetypes.dart';
import '../commands/commands.dart';
import '../components/components.dart';
import '../entities/entities.dart';
import '../errors/ecs_errors.dart';
import '../events/events.dart';
import '../resources/resources.dart';
import '../systems/systems.dart';
import 'world_observers.dart';

export 'world_extensions.dart';
export 'world_observers.dart';

/// Central coordinator for the ECS world.
///
/// World provides shortcuts and delegates to specialized registries:
/// - [ArchetypeRegistry]: Manages archetype graph and SoA storage
/// - [Entities]: Tracks entity lifecycle and location
/// - [ComponentRegistry]: Maps component types to IDs
/// - [ResourceRegistry]: Manages global resources
/// - [CommandQueue]: Defers structural changes
/// - [QueryCache]: Caches query results
/// - [SystemsRegistry]: Manages schedules and plugins
///
/// World coordinates initialization order and provides a unified API,
/// but delegates actual logic to the specialized registries.
/// Should never use commands directly -> for that, use [WorldCommands].
class World {
  World({
    final ArchetypeRegistry? archetypes,
    final Entities? entities,
    final CommandQueue? commandQueue,
    final ComponentRegistry? components,
    final ResourceRegistry? resources,
    final SystemsRegistry? systems,
    final QueryCache? queryCache,
    final EventRegistry? events,
    this.executionObserver,
    this.flushObserver,
  }) : systems = systems ?? SystemsRegistry() {
    // Initialize entities and components first
    this.entities = entities ?? Entities();
    this.components = components ?? ComponentRegistry();
    // Initialize command queue with world reference (needs this)
    this.commandQueue = commandQueue ?? CommandQueue(world: this);
    // Initialize resources with world reference
    this.resources = resources ?? ResourceRegistry(world: this);
    this.resources.push(ScheduleExecutionPolicyResource());
    this.resources.push(ScheduleJobResultQueueResource());
    this.resources.flush();
    this.events = events ?? EventRegistry(this);
    // Initialize query cache first (needed for archetype registry)
    this.queryCache = queryCache ?? QueryCache();
    // Initialize archetypes with component registry reference and query cache
    this.archetypes =
        archetypes ??
        ArchetypeRegistry(
          componentRegistry: this.components,
          queryCache: this.queryCache,
        );
  }

  late final ArchetypeRegistry archetypes;
  late final Entities entities;
  late final CommandQueue commandQueue;
  late final ComponentRegistry components;
  late final ResourceRegistry resources;
  late final QueryCache queryCache;
  late final EventRegistry events;
  final SystemsRegistry systems;
  bool isInitialized = false;
  bool enforceSoAForHotSchedules = false;
  int _hotScheduleDepth = 0;
  int _structuralRevision = 0;
  int _structuralRevisionBatchDepth = 0;
  bool _hasBatchedStructuralChange = false;

  /// Optional observer for schedule/system execution (debug/telemetry).
  EcsExecutionObserver? executionObserver;

  /// Optional observer for flush boundaries (debug/telemetry).
  WorldFlushObserver? flushObserver;

  /// Flag to prevent recursive flushing during command execution.
  /// Following Bevy's design of re-entrancy guards.
  bool _isFlushing = false;
  WorldCommands get commands => WorldCommands(queue: commandQueue);

  bool get isFlushing => _isFlushing;

  bool get isInHotSchedule => _hotScheduleDepth > 0;

  /// Monotonic revision for spawn, despawn, add, or remove structural changes.
  int get structuralRevision => _structuralRevision;

  /// Alias for [structuralRevision], intended for query membership caches.
  int get queryRevision => _structuralRevision;

  /// Sets the flushing state. Used internally by flush() to prevent recursion.
  @internal
  set isFlushing(final bool value) {
    assert(
      !value || !_isFlushing,
      'Attempted to set isFlushing=true while already flushing. '
      'This indicates a recursive flush attempt.',
    );
    _isFlushing = value;
  }

  /// Evict cached query results shaped by a structurally touched [componentId].
  @internal
  void evictQueriesForStructuralComponent(final ComponentId componentId) {
    queryCache.markStructurallyTouched(componentId);
  }

  @internal
  void recordStructuralChanged() {
    if (_structuralRevisionBatchDepth > 0) {
      _hasBatchedStructuralChange = true;
      return;
    }
    _structuralRevision += 1;
  }

  @internal
  void beginStructuralRevisionBatch() {
    _structuralRevisionBatchDepth += 1;
  }

  @internal
  void endStructuralRevisionBatch() {
    if (_structuralRevisionBatchDepth == 0) return;
    _structuralRevisionBatchDepth -= 1;
    if (_structuralRevisionBatchDepth == 0 && _hasBatchedStructuralChange) {
      _structuralRevision += 1;
      _hasBatchedStructuralChange = false;
    }
  }

  /// Validate component IDs against the hot schedule SoA guard.
  @internal
  void assertHotScheduleCompatible(final List<ComponentId> componentIds) {
    if (!enforceSoAForHotSchedules || !isInHotSchedule) {
      return;
    }
    for (final componentId in componentIds) {
      if (components.isObjectComponent(componentId)) {
        throw HotScheduleObjectComponentError(
          componentId,
          components.getType(componentId),
        );
      }
    }
  }

  @internal
  void enterHotSchedule() {
    _hotScheduleDepth++;
  }

  @internal
  void exitHotSchedule() {
    if (_hotScheduleDepth > 0) {
      _hotScheduleDepth--;
    }
  }
}
