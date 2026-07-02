// ignore_for_file: avoid_returning_this

import '../archetypes/archetypes.dart';
import '../commands/commands.dart';
import '../components/components.dart';
import '../world/world.dart';
import 'entities.dart';

/// Contains mutable world, passed by ref.
/// Provides Bevy-like API for working with entities in the world.
///
/// Should be validated before wrapping!
/// Use [World.getEntity] to validate and wrap an entity.
///
/// Suitable for structural changes.
/// For direct mutations see [WorldEntityMut]
class WorldEntity {
  WorldEntity({
    required this.world,
    required this.entity,
    required this.location,
  });
  final World world;
  final Entity entity;
  final EntityLocation location;

  // Cached archetype reference to avoid repeated findArchetypeIndex calls
  Archetype? _cachedArchetype;
  ArchetypeId? _cachedArchetypeId;

  Archetype get archetype {
    // Live id read: no EntityLocation alloc. Fast path O(1); miss path O(1)
    // registry lookup. Entity may migrate after WorldEntity construction.
    final currentArchetypeId = world.entities.archetypeIdOf(entity);

    if (_cachedArchetype != null && _cachedArchetypeId == currentArchetypeId) {
      return _cachedArchetype!;
    }

    _cachedArchetypeId = currentArchetypeId;
    _cachedArchetype = world
        .archetypes[world.archetypes.findArchetypeIndex(currentArchetypeId)];
    return _cachedArchetype!;
  }

  /// Check if entity is still valid (not despawned)
  ///
  /// Uses generation-based validation (like Bevy's Entities::is_valid).
  /// Checks both index and generation to detect stale entity references.
  /// O(1) lookup, doesn't trigger flushes.
  bool get isValid => world.entities.isAlive(entity);

  /// Despawn this entity
  /// Returns WorldEntity for method chaining
  WorldEntity despawn() {
    EntityCommands(queue: world.commandQueue, entity: entity).despawn();
    return this;
  }

  /// Get component of type T for this entity
  T? get<T extends Component>() => archetype.getComponentByEntity<T>(
    entity,
    world.components,
    world.entities,
  );

  ComponentId getComponentId<T extends Component>() =>
      world.components.getComponentId<T>();

  /// Check if entity has component of type T
  ///
  /// Uses non-throwing archetype signature check for efficient component
  /// existence verification.
  bool has<T extends Component>() =>
      archetype.signature.has(getComponentId<T>());

  /// Check if entity has component of type T without throwing.
  ///
  /// Uses archetype signature checking for efficient non-throwing component
  /// existence verification. Returns `false` if entity doesn't exist or
  /// component is not present.
  bool hasFast<T extends Component>() =>
      archetype.signature.has(getComponentId<T>());

  /// Insert/update component for this entity
  /// Returns WorldEntity for method chaining
  WorldEntity insert<T extends Component>(final T component) {
    EntityCommands(
      queue: world.commandQueue,
      entity: entity,
    ).upsert<T>(component);
    return this;
  }

  /// Remove component of type T from this entity
  /// Returns WorldEntity for method chaining
  WorldEntity remove<T extends Component>() {
    EntityCommands(queue: world.commandQueue, entity: entity).remove<T>();
    return this;
  }

  /// Convert to extension type wrapper for extension type facade access
  WorldEntityExtension toExtension() => WorldEntityExtension(this);

  /// Convert to mutable wrapper for direct component mutations
  WorldEntityMut toMut() => WorldEntityMut(this);
}
