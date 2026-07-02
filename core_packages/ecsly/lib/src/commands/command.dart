/// @docImport '../world/world.dart';
library;

import 'package:meta/meta.dart';

import '../components/components.dart';
import '../entities/entities.dart';
import '../resources/resources.dart';
import 'component_bundle.dart';

/// Command to batch add class components with data to multiple entities.
/// Components are added with provided data and processed efficiently.
class BatchAddClassComponentsCommand extends EcsCommand {
  BatchAddClassComponentsCommand(this.entities, this.components);
  final List<Entity> entities;
  final List<Component> components;
}

/// Command to batch add extension components to multiple entities.
/// Components are zero-initialized and added efficiently in archetype groups.
class BatchAddExtensionComponentsCommand extends EcsCommand {
  BatchAddExtensionComponentsCommand(this.entities, this.extensionComponents);
  final List<Entity> entities;
  // ClassComponent (Marker) -> ExtensionComponent
  final List<(Type, Type)> extensionComponents;
}

/// Command to batch remove components from multiple entities.
/// Supports both extension and class components with optimized archetype migration.
class BatchRemoveComponentsCommand extends EcsCommand {
  BatchRemoveComponentsCommand(this.entities, this.componentIds);
  final List<Entity> entities;
  final List<ComponentId> componentIds;
}

/// Command to spawn multiple entities with component bundles efficiently.
///
/// This batch operation minimizes command queue overhead and archetype creation
/// by processing entities in archetype groups. Supports both extension-based
/// (zero-cost) and class-based components with optimized handling for each.
class BatchSpawnCommand extends EcsCommand {
  BatchSpawnCommand(this.bundle, this.count);
  final ComponentBundle bundle;
  final int count;
}

/// Command to destroy multiple entities in one structural batch.
class BatchDestroyEntitiesCommand extends EcsCommand {
  BatchDestroyEntitiesCommand(this.entities);
  final List<Entity> entities;
}

class DeleteResourceCommand<T extends Resource> extends EcsCommand {
  DeleteResourceCommand(this.resource);
  final T resource;
}

/// Command to destroy an existing entity.
class DestroyEntityCommand extends EcsCommand {
  DestroyEntityCommand(this.entity);
  final Entity entity;
}

/// A sealed class for all commands that can be issued to the ECS.
///
/// Using a data-driven approach with sealed classes instead of function closures
/// avoids allocating numerous small objects for every command, reducing GC pressure.
/// The `CommandQueue` will interpret these data-only commands.
@immutable
sealed class EcsCommand {}

/// Command to remove a component from an existing entity.
class RemoveComponentCommand<T extends Component> extends EcsCommand {
  RemoveComponentCommand(this.entity, this.componentId);
  final Entity entity;
  final ComponentId componentId;
}

/// Command to spawn a new entity with a bundle of components.
///
/// Use only if you need to spawn an entity with multiple components.
/// Handles both class-based and extension-based components.
///
/// If you need to reserve Entity - just use [World.reserveEmptyEntity]
class SpawnEntityComponentsCommand extends EcsCommand {
  SpawnEntityComponentsCommand(this.bundle, this.entity);
  final ComponentBundle bundle;
  final Entity entity;
}

/// Command to add a component to an existing entity.
class UpsertComponentCommand<T extends Component> extends EcsCommand {
  UpsertComponentCommand(this.entity, this.component);
  final Entity entity;
  final T component;
}

class UpsertResourceCommand<T extends Resource> extends EcsCommand {
  UpsertResourceCommand(this.resource);
  final T resource;
}
