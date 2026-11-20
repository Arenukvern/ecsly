import 'package:ecsly/ecsly.dart';

import 'persistent_entity.dart';

/// O(1) identity → [Entity] lookup for persisted entities (ADR 0007 §3).
///
/// The index is a **cache, repaired at the consumers that need it**:
/// [register] happens at mint ([spawnPersistent]) and restore; [repair]
/// rebuilds from a full O(n) scan and is called by capture, restore and
/// reconcile before their lookups. Lookup performs no per-read validation —
/// a stale entry between a despawn and the next repair is acceptable because
/// every consumer that requires correctness repairs first. This is what lets
/// the index exist without core lifecycle hooks.
class PersistentEntityIndex extends Resource {
  final Map<String, Entity> _identities = <String, Entity>{};

  /// Number of indexed identities.
  int get length => _identities.length;

  /// Whether [identity] is currently indexed.
  bool contains(PersistentEntity identity) =>
      _identities.containsKey(identity.value);

  /// The entity indexed under [identity], or null.
  Entity? lookup(PersistentEntity identity) =>
      _identities[identity.value];

  /// Registers [entity] under [identity] (last write wins).
  void register(PersistentEntity identity, Entity entity) =>
      _identities[identity.value] = entity;

  /// Removes [identity] from the index.
  void unregister(PersistentEntity identity) =>
      _identities.remove(identity.value);

  /// All indexed identities.
  Iterable<PersistentEntity> get identities sync* {
    for (final value in _identities.keys) {
      yield PersistentEntity.fromJson(value);
    }
  }

  /// Rebuilds the index from a full scan of [world]'s persisted entities.
  ///
  /// O(n) in live entities; clears any drift (despawns, renames, manual
  /// spawns) since the last repair.
  void repair(World world) {
    registerPersistentEntity(world);
    _identities.clear();
    final identityId = world.components.getComponentIdByType(
      PersistentEntityComponent,
    );
    if (identityId == null) return;
    for (final archetype in world.archetypes.all) {
      if (!archetype.signature.has(identityId)) continue;
      for (final entity in archetype.entities) {
        final identity = persistentEntityOf(world, entity);
        if (identity == null) continue;
        _identities[identity.value] = entity;
      }
    }
  }
}
