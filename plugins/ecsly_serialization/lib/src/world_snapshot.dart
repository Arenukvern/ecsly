import 'package:ecsly/ecsly.dart';

import 'column_entity_snapshot.dart';
import 'component_naming.dart';
import 'entity_refs.dart';
import 'object_component_codec.dart';
import 'persistent_entity.dart';
import 'resource_snapshot.dart';

/// Version of the world snapshot envelope format.
///
/// v4: durable identity is a [PersistentEntity] (String); `EntityEntry`
/// carries `identity`. v3 and earlier carried an int `persistentId`;
/// decoding normalizes it, so pre-v4 snapshots load without migration.
const int worldSnapshotVersion = 4;

/// A full snapshot of a world: resources plus all persisted entities
/// (carrying [PersistentEntityComponent]) with their column data and
/// structural layout.
///
/// Identity model (matching Bevy/networked-ECS practice, ADR 0007):
/// - Runtime `Entity` handles are world-local and never serialized as
///   identity. Persisted entities carry a [PersistentEntityComponent] whose
///   [PersistentEntity] value is the stable cross-session key; it is
///   re-attached on restore and used to resolve entity references *within*
///   the snapshot.
/// - Component identity is by stable registered name (falling back to the
///   type name) in [componentIds]; restore remaps data onto the target
///   world's own IDs, so snapshots survive registration reordering,
///   additions, and removals.
///
/// Restore spawns fresh entities into the target world — no pre-spawned
/// structure required. Works into completely empty worlds.
class WorldSnapshot {
  /// Creates a world snapshot.
  const WorldSnapshot({
    required this.version,
    required this.schemaVersion,
    required this.componentIds,
    required this.resources,
    required this.entities,
  });

  /// Envelope format version.
  final int version;

  /// App-owned logical schema version. Bump it when the meaning of saved
  /// data changes in ways a name remap cannot express; pair with a
  /// [SnapshotMigration] so older saves keep loading.
  final int schemaVersion;

  /// Component snapshot identity → source-world `ComponentId` value.
  ///
  /// This is the stable identity layer: names travel with the snapshot,
  /// IDs stay world-local. [PersistentEntityComponent] is implicit and not
  /// listed here.
  final Map<String, int> componentIds;

  /// Resource snapshot keyed by resource snapshot identity.
  final Map<String, Object?> resources;

  /// Per-entity snapshots, each carrying its [EntityEntry.identity].
  final List<EntityEntry> entities;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'schemaVersion': schemaVersion,
    'componentIds': componentIds,
    'resources': resources,
    'entities': entities.map((e) => e.toJson()).toList(growable: false),
  };

  /// Deserializes from a JSON-compatible map.
  ///
  /// Pre-v4 envelopes (int `persistentId` per entity) are normalized to the
  /// v4 `identity` form during entity decoding.
  // ignore: prefer_constructors_over_static_methods
  static WorldSnapshot fromJson(Map<String, Object?> json) =>
      WorldSnapshot(
        version: (json['version'] as num?)?.toInt() ?? worldSnapshotVersion,
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        componentIds: ((json['componentIds'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
        resources: (json['resources'] as Map<String, Object?>?) ?? const {},
        entities: ((json['entities'] as List<Object?>?) ?? const [])
            .whereType<Map<String, Object?>>()
            .map(EntityEntry.fromJson)
            .toList(growable: false),
      );
}

/// Serialized state of a single entity.
class EntityEntry {
  /// Creates an entity entry.
  ///
  /// [identity] is the stable cross-session identity (from the entity's
  /// [PersistentEntityComponent]). [components] lists the component snapshot
  /// identities the entity carries besides the identity component itself.
  /// [columns] is the flat column data (including the identity component's
  /// object-column entry).
  const EntityEntry({
    required this.identity,
    required this.components,
    required this.columns,
  });

  /// Stable cross-session identity from the entity's identity component.
  final String identity;

  /// Component snapshot identities this entity carries (structural
  /// signature), excluding the identity component itself.
  final List<String> components;

  /// Flat column data for this entity.
  final Map<String, Object?> columns;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity,
    'components': components,
    'columns': columns,
  };

  /// Deserializes from a JSON-compatible map.
  ///
  /// Pre-v4 entries carry an int `persistentId` (or its String form); it is
  /// normalized to a decimal [PersistentEntity] identity.
  // ignore: prefer_constructors_over_static_methods
  static EntityEntry fromJson(Map<String, Object?> json) => EntityEntry(
    identity: PersistentEntity.fromJson(
      json['identity'] ?? json['persistentId'],
    ).value,
    components: ((json['components'] as List<Object?>?) ?? const [])
        .whereType<String>()
        .toList(growable: false),
    columns: (json['columns'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v),
    ),
  );
}

/// How [restoreWorldSnapshot] applies a snapshot to [world].
enum WorldSnapshotRestoreMode {
  /// Spawn fresh entities for each snapshot entry (default save/load path).
  spawn,

  /// Reconcile an existing world by identity: update values, add/remove
  /// components to match, optionally despawn persisted entities missing
  /// from the snapshot. Entities without an identity component are left
  /// untouched.
  reconcile,
}

/// Options controlling whole-world capture and restore.
class WorldSnapshotOptions {
  /// Creates snapshot options.
  const WorldSnapshotOptions({
    this.includeOnly,
    this.codecs,
    this.schemaVersion = 1,
    this.strictComponents = false,
    this.restoreMode = WorldSnapshotRestoreMode.spawn,
    this.reconcileDespawnAbsent = true,
  });

  /// Restrict capture/restore to these component IDs (excluding
  /// [PersistentEntityComponent], which is always handled).
  final Set<ComponentId>? includeOnly;

  /// Codecs for object-tier components.
  final ObjectComponentCodecRegistry? codecs;

  /// App-owned logical schema version stored in the snapshot.
  final int schemaVersion;

  /// When true, restore throws if the snapshot contains a component that is
  /// not registered in the target world. Default is to skip silently.
  final bool strictComponents;

  /// Selects spawn-vs-reconcile behavior for [restoreWorldSnapshot].
  final WorldSnapshotRestoreMode restoreMode;

  /// When [restoreMode] is [WorldSnapshotRestoreMode.reconcile], despawn
  /// persisted entities that are absent from the snapshot. Set false when
  /// applying a partial outcome snapshot (for example per-command replay).
  final bool reconcileDespawnAbsent;
}

/// Captures a full [WorldSnapshot] from [world].
///
/// Only entities carrying a [PersistentEntityComponent] are captured. The
/// world is flushed first so pending commands and resource pushes are
/// reflected in the snapshot. [resourceRegistry] supplies stable names for
/// registered snapshotable resources.
WorldSnapshot captureWorldSnapshot(
  World world, {
  WorldSnapshotOptions options = const WorldSnapshotOptions(),
  SnapshotResourceRegistry? resourceRegistry,
}) {
  registerPersistentEntity(world);
  world.flush();

  final identityId = _identityComponentIdOrNull(world)!;
  final componentIds = <String, int>{};
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(identityId)) continue;
    for (final componentId in archetype.componentIds) {
      if (componentId == identityId) continue;
      if (options.includeOnly != null &&
          !options.includeOnly!.contains(componentId)) {
        continue;
      }
      final name = componentSnapshotName(world, componentId);
      if (name != null) {
        componentIds[name] = componentId.value;
      }
    }
  }

  final entities = <EntityEntry>[];
  final seenIds = <String>{};
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(identityId)) continue;
    for (final entity in archetype.entities) {
      final identity = persistentEntityOf(world, entity);
      if (identity == null) continue;
      if (!seenIds.add(identity.value)) {
        throw StateError(
          'Duplicate ${identity.value} during capture. Persistent '
          'identities must be unique among persisted entities — allocate '
          'them through a PersistentEntityAllocator.',
        );
      }
      final columns = captureEntityColumns(
        world,
        entity,
        includeOnly: options.includeOnly,
        codecs: options.codecs,
      );
      if (columns == null) continue;
      entities.add(
        EntityEntry(
          identity: identity.value,
          components: [
            for (final id in archetype.componentIds)
              if (id != identityId) ...?componentSnapshotNameOrNull(world, id),
          ],
          columns: columns,
        ),
      );
    }
  }

  return WorldSnapshot(
    version: worldSnapshotVersion,
    schemaVersion: options.schemaVersion,
    componentIds: componentIds,
    resources: captureResourceSnapshot(world, registry: resourceRegistry),
    entities: entities,
  );
}

/// Restores a [WorldSnapshot] into [world].
///
/// Default [WorldSnapshotOptions.restoreMode] spawns fresh entities. With
/// [WorldSnapshotRestoreMode.reconcile], updates the live world in place by
/// identity (see [WorldSnapshotOptions.reconcileDespawnAbsent]).
///
/// Restores instances from the registry's registered sample instances
/// (the component-side mirror of `sampleEvent`). Component types that are
/// needed at spawn time must be registered with a `sample:` instance;
/// restore throws a [StateError] naming the missing type otherwise.
///
/// When the world holds a [PersistentEntityAllocatorResource], restore
/// auto-adopts: the allocator grows past every live identity (including
/// pre-existing ones a partial restore left in place), so identities minted
/// after restore never collide. When the world holds a
/// [PersistentEntityIndex], it is repaired — identity lookups stay O(1).
///
/// Returns the mapping of snapshot identities to live entities.
Map<String, Entity> restoreWorldSnapshot(
  World world,
  WorldSnapshot snapshot, {
  Map<String, SnapshotResourceFactory> resourceFactories =
      const <String, SnapshotResourceFactory>{},
  SnapshotResourceRegistry? resourceRegistry,
  Map<String, Component Function()> componentFactories =
      const <String, Component Function()>{},
  WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  registerPersistentEntity(world);
  world.flush();

  if (options.restoreMode == WorldSnapshotRestoreMode.reconcile) {
    return _reconcileWorldSnapshot(
      world,
      snapshot,
      resourceFactories: resourceFactories,
      resourceRegistry: resourceRegistry,
      componentFactories: componentFactories,
      options: options,
    );
  }

  final idRemap = _buildIdRemap(world, snapshot, options);
  final index = world.maybeGetResource<PersistentEntityIndex>();
  index?.repair(world);
  final newEntities = <String, Entity>{};
  for (final entry in snapshot.entities) {
    final existing = _entityWithIdentity(world, entry.identity, index);
    if (existing != null) {
      newEntities[entry.identity] = existing;
      continue;
    }
    newEntities[entry.identity] = _spawnEntityFromEntry(
      world,
      entry,
      componentFactories: componentFactories,
      options: options,
    );
  }
  world.flush();

  final resolver = EntityRefResolver(newEntities);
  for (final entry in snapshot.entities) {
    final entity = newEntities[entry.identity];
    if (entity == null) continue;
    restoreEntityColumns(
      world,
      entity,
      _remapColumns(entry.columns, idRemap),
      refs: resolver,
      includeOnly: options.includeOnly,
      codecs: options.codecs,
    );
  }

  restoreResourceSnapshot(
    world,
    snapshot.resources,
    factories: resourceFactories,
    registry: resourceRegistry,
    refs: resolver,
  );
  _adoptIdentityState(world);
  return newEntities;
}

/// Reconciles [snapshot] into a non-empty [world] by identity.
///
/// Convenience wrapper setting [WorldSnapshotOptions.restoreMode.reconcile].
Map<String, Entity> reconcileWorldSnapshot(
  World world,
  WorldSnapshot snapshot, {
  Map<String, SnapshotResourceFactory> resourceFactories =
      const <String, SnapshotResourceFactory>{},
  SnapshotResourceRegistry? resourceRegistry,
  Map<String, Component Function()> componentFactories =
      const <String, Component Function()>{},
  WorldSnapshotOptions options = const WorldSnapshotOptions(),
  bool despawnAbsent = true,
}) =>
    restoreWorldSnapshot(
      world,
      snapshot,
      resourceFactories: resourceFactories,
      resourceRegistry: resourceRegistry,
      componentFactories: componentFactories,
      options: WorldSnapshotOptions(
        includeOnly: options.includeOnly,
        codecs: options.codecs,
        schemaVersion: options.schemaVersion,
        strictComponents: options.strictComponents,
        restoreMode: WorldSnapshotRestoreMode.reconcile,
        reconcileDespawnAbsent: despawnAbsent,
      ),
    );

Map<String, Entity> _reconcileWorldSnapshot(
  World world,
  WorldSnapshot snapshot, {
  required Map<String, SnapshotResourceFactory> resourceFactories,
  required SnapshotResourceRegistry? resourceRegistry,
  required Map<String, Component Function()> componentFactories,
  required WorldSnapshotOptions options,
}) {
  final idRemap = _buildIdRemap(world, snapshot, options);
  final snapshotIds = snapshot.entities
      .map((e) => e.identity)
      .toSet();
  _assertUniqueIdentities(snapshotIds, snapshot.entities);

  final index = world.maybeGetResource<PersistentEntityIndex>();
  index?.repair(world);

  if (options.reconcileDespawnAbsent) {
    for (final entity in _allPersistedEntities(world)) {
      final identity = persistentEntityOf(world, entity);
      if (identity == null) continue;
      if (!snapshotIds.contains(identity.value)) {
        world.despawnEntity(entity);
      }
    }
    world.flush();
    index?.repair(world);
  }

  final live = <String, Entity>{};
  for (final entry in snapshot.entities) {
    var entity = _entityWithIdentity(world, entry.identity, index);
    if (entity == null) {
      entity = _spawnEntityFromEntry(
        world,
        entry,
        componentFactories: componentFactories,
        options: options,
      );
    } else {
      _reconcileEntityComponents(
        world,
        entity,
        entry,
        componentFactories: componentFactories,
        options: options,
      );
    }
    live[entry.identity] = entity;
  }
  world.flush();

  final resolver = EntityRefResolver(live);
  for (final entry in snapshot.entities) {
    final entity = live[entry.identity];
    if (entity == null) continue;
    restoreEntityColumns(
      world,
      entity,
      _remapColumns(entry.columns, idRemap),
      refs: resolver,
      includeOnly: options.includeOnly,
      codecs: options.codecs,
    );
  }

  restoreResourceSnapshot(
    world,
    snapshot.resources,
    factories: resourceFactories,
    registry: resourceRegistry,
    refs: resolver,
  );
  _adoptIdentityState(world);
  return live;
}

/// Repairs the index (post-flush) and grows the allocator past every live
/// identity — the auto-adopt step (ADR 0007 §2/§3).
void _adoptIdentityState(World world) {
  final index = world.maybeGetResource<PersistentEntityIndex>();
  final allocatorResource = world.maybeGetResource<PersistentEntityAllocatorResource>();
  if (allocatorResource != null) {
    if (index == null) {
      // No index: adopt over a full scan of live persisted entities.
      allocatorResource.allocator.adoptMax(
        [
          for (final entity in _allPersistedEntities(world))
            ?persistentEntityOf(world, entity),
        ].whereType<PersistentEntity>(),
      );
    } else {
      index.repair(world);
      allocatorResource.allocator.adoptMax(index.identities);
    }
  } else {
    index?.repair(world);
  }
}

void _assertUniqueIdentities(
  Set<String> identities,
  List<EntityEntry> entities,
) {
  if (identities.length == entities.length) return;
  throw StateError(
    'Snapshot contains duplicate persistent identities; persisted '
    'identities must be unique.',
  );
}

Iterable<Entity> _allPersistedEntities(World world) sync* {
  final identityId = _identityComponentIdOrNull(world);
  if (identityId == null) return;
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(identityId)) continue;
    for (final entity in archetype.entities) {
      yield entity;
    }
  }
}

Entity _spawnEntityFromEntry(
  World world,
  EntityEntry entry, {
  required Map<String, Component Function()> componentFactories,
  required WorldSnapshotOptions options,
}) {
  final identity = PersistentEntity.fromJson(entry.identity);
  final instances = <Component>[PersistentEntityComponent(identity)];
  final extensions = <(Type, Type)>[];
  for (final typeName in entry.components) {
    final localType = componentTypeForSnapshotName(world, typeName);
    if (localType == null) {
      if (options.strictComponents) {
        throw StateError(
          'Snapshot entity ${entry.identity} requires component '
          '"$typeName" which is not registered in the target world '
          '(strictComponents=true).',
        );
      }
      continue;
    }
    final localId = world.components.getComponentIdByType(localType)!;
    if (world.components.isObjectComponent(localId)) {
      final sample =
          componentFactories[typeName]?.call() ??
          world.components.sampleFor(localId);
      if (sample == null) {
        throw StateError(
          'No sample registered for object component "$typeName". Register '
          'it with registerObjectComponent<$typeName>(sample: ...) or '
          'provide a componentFactories entry in restoreWorldSnapshot.',
        );
      }
      instances.add(sample);
    } else {
      final extensionType = world.components.componentFacadeRegistry
          .getExtensionType(localId);
      if (extensionType != null && extensionType != Object) {
        extensions.add((localType, extensionType));
      }
    }
  }
  return world.spawnComponents(instances, extensions);
}

void _reconcileEntityComponents(
  World world,
  Entity entity,
  EntityEntry entry, {
  required Map<String, Component Function()> componentFactories,
  required WorldSnapshotOptions options,
}) {
  final identityId = _identityComponentIdOrNull(world)!;
  final (ext, ok) = world.getEntityExtension(entity);
  if (!ok) return;

  final desired = entry.components.toSet();
  final currentNames = <String>{};
  for (final componentId in ext.archetype.componentIds) {
    if (componentId == identityId) continue;
    final name = componentSnapshotName(world, componentId);
    if (name != null) currentNames.add(name);
  }

  for (final typeName in currentNames.difference(desired)) {
    final localType = componentTypeForSnapshotName(world, typeName);
    if (localType == null) continue;
    final componentId = world.components.getComponentIdByType(localType);
    if (componentId == null) continue;
    world.commandQueue.push(
      RemoveComponentCommand<Component>(entity, componentId),
    );
  }
  world.flush();

  for (final typeName in desired.difference(currentNames)) {
    final localType = componentTypeForSnapshotName(world, typeName);
    if (localType == null) {
      if (options.strictComponents) {
        throw StateError(
          'Snapshot entity ${entry.identity} requires component '
          '"$typeName" which is not registered in the target world '
          '(strictComponents=true).',
        );
      }
      continue;
    }
    final localId = world.components.getComponentIdByType(localType)!;
    if (world.components.isObjectComponent(localId)) {
      final sample =
          componentFactories[typeName]?.call() ??
          world.components.sampleFor(localId);
      if (sample == null) {
        throw StateError(
          'No sample registered for object component "$typeName". Register '
          'it with registerObjectComponent<$typeName>(sample: ...) or '
          'provide a componentFactories entry in restoreWorldSnapshot.',
        );
      }
      world.commandQueue.push(
        UpsertComponentCommand<Component>(entity, sample),
      );
    } else {
      final extensionType = world.components.componentFacadeRegistry
          .getExtensionType(localId);
      if (extensionType != null && extensionType != Object) {
        world.spawnBundle(
          entity,
          ComponentBundle.fromLists(const [], [(localType, extensionType)]),
        );
      }
    }
  }
  world.flush();
}

/// Finds the live entity carrying [identity].
///
/// Index-first (O(1)) when [index] is supplied — callers repair it before
/// the lookup loop; otherwise a linear scan (legacy behavior).
Entity? _entityWithIdentity(
  World world,
  String identity,
  PersistentEntityIndex? index,
) {
  if (index != null) return index.lookup(PersistentEntity.fromJson(identity));
  final identityId = _identityComponentIdOrNull(world);
  if (identityId == null) return null;
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(identityId)) continue;
    for (final entity in archetype.entities) {
      final candidate = persistentEntityOf(world, entity);
      if (candidate?.value == identity) return entity;
    }
  }
  return null;
}

/// Builds snapshot-ID → local-ID remap from the component identity table.
///
/// Resolution uses the target world's stable component names first (O(1)),
/// falling back to type names, so restoring into a fresh/empty world works
/// without any prior capture.
Map<int, int> _buildIdRemap(
  World world,
  WorldSnapshot snapshot,
  WorldSnapshotOptions options,
) {
  final localIds = <String, int>{};
  for (final entry in world.components.registeredTypes.entries) {
    final name = world.components.nameOf(entry.key) ?? entry.value.toString();
    localIds[name] = entry.key.value;
  }

  final remap = <int, int>{};
  for (final entry in snapshot.componentIds.entries) {
    final localIdValue = localIds[entry.key];
    if (localIdValue == null) {
      if (options.strictComponents) {
        throw StateError(
          'Snapshot contains component "${entry.key}" which is not registered '
          'in the target world (strictComponents=true).',
        );
      }
      continue;
    }
    remap[entry.value] = localIdValue;
  }
  return remap;
}

/// Rewrites positional and object keys from snapshot IDs to local IDs.
Map<String, Object?> _remapColumns(
  Map<String, Object?> columns,
  Map<int, int> idRemap,
) {
  if (idRemap.isEmpty) return columns;
  final remapped = <String, Object?>{};
  for (final entry in columns.entries) {
    final key = entry.key;
    if (key.startsWith('obj_')) {
      final snapshotId = int.tryParse(key.substring(4));
      final localId = snapshotId == null ? null : idRemap[snapshotId];
      if (localId != null) {
        remapped['obj_$localId'] = entry.value;
      }
      continue;
    }
    final underscore = key.indexOf('_');
    if (underscore <= 0) {
      remapped[key] = entry.value;
      continue;
    }
    final snapshotId = int.tryParse(key.substring(0, underscore));
    final offset = key.substring(underscore + 1);
    if (snapshotId == null || int.tryParse(offset) == null) {
      remapped[key] = entry.value;
      continue;
    }
    final localId = idRemap[snapshotId];
    if (localId == null) continue; // component removed from target world
    remapped['${localId}_$offset'] = entry.value;
  }
  return remapped;
}

List<String>? componentSnapshotNameOrNull(
  World world,
  ComponentId componentId,
) {
  final name = componentSnapshotName(world, componentId);
  return name == null ? null : [name];
}

ComponentId? _identityComponentIdOrNull(World world) =>
    world.components.getComponentIdByType(PersistentEntityComponent);
