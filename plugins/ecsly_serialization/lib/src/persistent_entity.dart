import 'package:ecsly/ecsly.dart';

import 'persistent_entity_allocator.dart';
import 'persistent_entity_index.dart';

export 'persistent_entity_allocator.dart';
export 'persistent_entity_index.dart';
// The durable-identity type lives in core's public barrel; re-export it so
// one import serves the whole identity model.
export 'package:ecsly/ecsly.dart' show PersistentEntity;

/// Marker + identity component marking an entity as persistable.
///
/// Only entities carrying [PersistentEntityComponent] are captured by
/// `captureWorldSnapshot`; everything else (particles, VFX, transient state)
/// is treated as runtime-only. The [value] is the stable cross-session
/// identity: it travels with the snapshot and is re-attached on restore, so
/// references and app-side lookups survive world-to-world transfers.
///
/// Allocate identities through a [PersistentEntityAllocator] — preferably
/// via [spawnPersistent] or `SerializationPlugin(manageIds: true)` — so the
/// uniqueness invariant (capture throws on duplicates) cannot be broken by
/// an ad-hoc construction.
///
/// Register it in the world via [registerPersistentEntity] (done
/// automatically by capture and restore).
class PersistentEntityComponent extends Component {
  /// Creates the identity component with the given stable [value].
  const PersistentEntityComponent(this.value);

  /// Stable cross-session identity. Must be unique among persisted entities
  /// in a world; duplicates fail capture loudly.
  final PersistentEntity value;

  @override
  String toString() => 'PersistentEntityComponent($value)';
}

/// Ensures [PersistentEntityComponent] is registered in [world]. Idempotent.
void registerPersistentEntity(World world) {
  if (world.components.getComponentIdByType(PersistentEntityComponent) ==
      null) {
    world.components.registerObjectComponent<PersistentEntityComponent>(
      name: 'ecsly.persistent_entity',
      sample: const PersistentEntityComponent(PersistentEntity.zero),
    );
  }
}

/// Reads the [PersistentEntityComponent] of [entity], or null when absent.
PersistentEntityComponent? persistentEntityComponentOf(
  World world,
  Entity entity,
) {
  try {
    final location = world.entities.getLocation(entity);
    if (location.archetypeId == ArchetypeId.zero) return null;
    final archetypeIndex = world.archetypes.findArchetypeIndex(
      location.archetypeId,
    );
    return world
        .archetypes[archetypeIndex]
        .getComponentByEntity<PersistentEntityComponent>(
          entity,
          world.components,
          world.entities,
        );
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}

/// Reads the stable [PersistentEntity] of [entity], or null when the entity
/// is not persisted.
PersistentEntity? persistentEntityOf(
  World world,
  Entity entity,
) => persistentEntityComponentOf(world, entity)?.value;

/// Extension adding persistence-aware spawning to [World].
extension PersistentSpawnWorldExtension on World {
  /// Spawns an entity with a freshly allocated [PersistentEntityComponent]
  /// attached — the one allocation path for persistable entities.
  ///
  /// Requires a [PersistentEntityAllocatorResource] in [world] (installed by
  /// `SerializationPlugin(manageIds: true)` or directly), and registers the
  /// new identity in the [PersistentEntityIndex] when present.
  ///
  /// Throws [StateError] when no allocator is installed, naming the fix.
  Entity spawnPersistent(
    List<Component> instances, {
    List<(Type, Type)> extensions = const <(Type, Type)>[],
  }) {
    registerPersistentEntity(this);
    final allocatorResource = maybeGetResource<PersistentEntityAllocatorResource>();
    if (allocatorResource == null) {
      throw StateError(
        'spawnPersistent requires a PersistentEntityAllocatorResource. '
        'Install it via SerializationPlugin(manageIds: true) or '
        'upsertResource(PersistentEntityAllocatorResource(...)).',
      );
    }
    final identity = allocatorResource.allocator.next();
    final index = maybeGetResource<PersistentEntityIndex>();
    if (index != null && index.contains(identity)) {
      throw StateError(
        'Persistent identity collision on spawn: $identity is already in '
        'use. The allocator state is out of sync with the world — restore '
        'must adopt, or the allocator was replaced.',
      );
    }
    final entity = spawnComponents([
      PersistentEntityComponent(identity),
      ...instances,
    ], extensions);
    index?.register(identity, entity);
    return entity;
  }
}
