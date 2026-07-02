import '../../components/components.dart';
import '../../entities/entities.dart';
import '../../resources/resources.dart';
import '../command.dart';
import '../command_queue.dart';
import '../component_bundle.dart';
import 'entity_commands.dart';

/// responsible for managing world.
/// for specific needs, use [EntityCommands]
class WorldCommands {
  const WorldCommands({required this.queue});
  final CommandQueue queue;
}

extension WorldCommandsX on WorldCommands {
  /// Batch add class components with data to multiple entities (deferred execution).
  ///
  /// Components are added with provided data and processed efficiently.
  /// Execution is deferred until the next flush.
  ///
  /// [entities] - List of entities to add components to
  /// [components] - List of component instances with data
  void batchAddClassComponents(
    final List<Entity> entities,
    final List<Component> components,
  ) {
    if (entities.isEmpty || components.isEmpty) return;
    queue.push(BatchAddClassComponentsCommand(entities, components));
  }

  /// Batch add extension components to multiple entities (deferred execution).
  ///
  /// Components are zero-initialized and added efficiently in archetype groups.
  /// Execution is deferred until the next flush.
  ///
  /// [entities] - List of entities to add components to
  /// [componentSpecs] - List of (ComponentType, ExtensionType) pairs
  void batchAddExtensionComponents(
    final List<Entity> entities,
    final List<(Type, Type)> componentSpecs,
  ) {
    if (entities.isEmpty || componentSpecs.isEmpty) return;
    queue.push(BatchAddExtensionComponentsCommand(entities, componentSpecs));
  }

  /// Batch remove components from multiple entities (deferred execution).
  ///
  /// Supports both extension and class components with optimized archetype grouping.
  /// Execution is deferred until the next flush.
  ///
  /// [entities] - List of entities to remove components from
  /// [componentIds] - List of component IDs to remove
  void batchRemoveComponents(
    final List<Entity> entities,
    final List<ComponentId> componentIds,
  ) {
    if (entities.isEmpty || componentIds.isEmpty) return;
    queue.push(BatchRemoveComponentsCommand(entities, componentIds));
  }

  /// Spawn multiple entities with the same component bundle efficiently.
  ///
  /// This batch operation is optimized for large-scale spawning (100-10000 entities)
  /// and provides significant performance improvements over individual spawn calls.
  ///
  /// Example:
  /// ```dart
  /// // Instead of:
  /// for (var i = 0; i < 10000; i++) {
  ///   world.commands.spawnBundle(world.entities.create(), bundle);
  /// }
  ///
  /// // Use:
  /// world.commands.batchSpawn(bundle, 10000);
  /// ```
  void batchSpawn(final ComponentBundle bundle, final int count) {
    if (count <= 0) return;
    queue.push(BatchSpawnCommand(bundle, count));
  }

  void despawn(final Entity entity) => queue.push(DestroyEntityCommand(entity));

  /// Destroy multiple entities in one deferred structural batch.
  void batchDespawn(final List<Entity> entities) {
    if (entities.isEmpty) return;
    queue.push(BatchDestroyEntitiesCommand(entities));
  }

  void remove<T extends Component>(final Entity entity) {
    final componentId = queue.world.components.getComponentId<T>();
    queue.push(RemoveComponentCommand<T>(entity, componentId));
  }

  void removeResource<T extends Resource>(final T resource) =>
      queue.push(DeleteResourceCommand<T>(resource));

  /// Spawn an entity with a bundle of components atomically.
  ///
  /// This is more efficient than multiple upsert calls as it allows
  /// the component registry to process all components together.
  EntityCommands spawnBundle(
    final Entity entity,
    final ComponentBundle bundle,
  ) {
    queue.push(SpawnEntityComponentsCommand(bundle, entity));
    return EntityCommands(queue: queue, entity: entity);
  }

  /// Upsert a component on an existing entity.
  ///
  /// [entity] - The entity to upsert the component on
  /// [component] - The component to upsert
  void upsert<T extends Component>(final Entity entity, final T component) =>
      queue.push(UpsertComponentCommand(entity, component));

  /// Upsert a resource on the world.
  ///
  /// [resource] - The resource to upsert
  void upsertResource<T extends Resource>(final T resource) =>
      queue.push(UpsertResourceCommand(resource));
}
