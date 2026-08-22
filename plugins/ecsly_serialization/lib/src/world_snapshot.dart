import 'package:ecsly/ecsly.dart';

import 'column_entity_snapshot.dart';
import 'object_component_codec.dart';
import 'persistent_id.dart';
import 'resource_snapshot.dart';

/// Version of the world snapshot envelope format.
const int worldSnapshotVersion = 3;

/// A full snapshot of a world: resources plus all [PersistentId]-tagged
/// entities with their column data and structural layout.
///
/// Identity model (matching Bevy/networked-ECS practice):
/// - Runtime `Entity` handles are world-local and never serialized as
///   identity. Persisted entities carry a [PersistentId] component whose
///   value is the stable cross-session key; it is re-attached on restore and
///   used to resolve entity references *within* the snapshot.
/// - Component identity is by type name ([componentIds]); restore remaps data
///   onto the target world's own IDs, so snapshots survive registration
///   reordering, additions, and removals.
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

  /// Component type name → source-world `ComponentId` value.
  ///
  /// This is the stable identity layer: names travel with the snapshot,
  /// IDs stay world-local. [PersistentId] is implicit and not listed here.
  final Map<String, int> componentIds;

  /// Resource snapshot keyed by resource type name.
  final Map<String, Object?> resources;

  /// Per-entity snapshots, each carrying its [EntityEntry.persistentId].
  final List<EntityEntry> entities;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'schemaVersion': schemaVersion,
    'componentIds': componentIds,
    'resources': resources,
    'entities': entities.map((final e) => e.toJson()).toList(growable: false),
  };

  /// Deserializes from a JSON-compatible map.
  // ignore: prefer_constructors_over_static_methods
  static WorldSnapshot fromJson(final Map<String, Object?> json) =>
      WorldSnapshot(
        version: (json['version'] as num?)?.toInt() ?? worldSnapshotVersion,
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        componentIds: ((json['componentIds'] as Map?) ?? const {}).map(
          (final k, final v) => MapEntry(k.toString(), (v as num).toInt()),
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
  /// [persistentId] is the stable cross-session identity (from the entity's
  /// [PersistentId] component). [components] lists the component type names
  /// the entity carries besides [PersistentId]. [columns] is the flat column
  /// data (including PersistentId's object-column entry).
  const EntityEntry({
    required this.persistentId,
    required this.components,
    required this.columns,
  });

  /// Stable cross-session identity from the entity's [PersistentId].
  final int persistentId;

  /// Component type names this entity carries (structural signature),
  /// excluding [PersistentId] itself.
  final List<String> components;

  /// Flat column data for this entity.
  final Map<String, Object?> columns;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'persistentId': persistentId,
    'components': components,
    'columns': columns,
  };

  /// Deserializes from a JSON-compatible map.
  // ignore: prefer_constructors_over_static_methods
  static EntityEntry fromJson(final Map<String, Object?> json) => EntityEntry(
    persistentId: (json['persistentId'] as num?)?.toInt() ?? 0,
    components: ((json['components'] as List<Object?>?) ?? const [])
        .whereType<String>()
        .toList(growable: false),
    columns: (json['columns'] as Map? ?? const {}).map(
      (final k, final v) => MapEntry(k.toString(), v),
    ),
  );
}

/// Options controlling whole-world capture and restore.
class WorldSnapshotOptions {
  /// Creates snapshot options.
  const WorldSnapshotOptions({
    this.includeOnly,
    this.codecs,
    this.schemaVersion = 1,
    this.strictComponents = false,
  });

  /// Restrict capture/restore to these component IDs (excluding
  /// [PersistentId], which is always handled).
  final Set<ComponentId>? includeOnly;

  /// Codecs for object-tier components.
  final ObjectComponentCodecRegistry? codecs;

  /// App-owned logical schema version stored in the snapshot.
  final int schemaVersion;

  /// When true, restore throws if the snapshot contains a component that is
  /// not registered in the target world. Default is to skip silently.
  final bool strictComponents;
}

/// Captures a full [WorldSnapshot] from [world].
///
/// Only entities carrying a [PersistentId] component are captured. The world
/// is flushed first so pending commands and resource pushes are reflected in
/// the snapshot.
WorldSnapshot captureWorldSnapshot(
  final World world, {
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  registerPersistentId(world);
  world.flush();

  final persistentIdId = _persistentIdComponentIdOrNull(world)!;
  final componentIds = <String, int>{};
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(persistentIdId)) continue;
    for (final componentId in archetype.componentIds) {
      if (componentId == persistentIdId) continue;
      if (options.includeOnly != null &&
          !options.includeOnly!.contains(componentId)) {
        continue;
      }
      final typeName = _componentTypeName(world, componentId);
      if (typeName != null) {
        componentIds[typeName] = componentId.value;
      }
    }
  }

  final entities = <EntityEntry>[];
  final seenIds = <int>{};
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(persistentIdId)) continue;
    for (final entity in archetype.entities) {
      final pid = persistentIdOf(world, entity);
      if (pid == null) continue;
      if (!seenIds.add(pid.value)) {
        throw StateError(
          'Duplicate PersistentId(${pid.value}) during capture. Persistent '
          'ids must be unique among persisted entities.',
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
          persistentId: pid.value,
          components: [
            for (final id in archetype.componentIds)
              if (id != persistentIdId) ...?_componentTypeNameOrNull(world, id),
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
    resources: captureResourceSnapshot(world),
    entities: entities,
  );
}

/// Restores a [WorldSnapshot] into [world], spawning fresh entities.
///
/// The target world may be completely empty — structural layout travels with
/// the snapshot as component names. Entities are spawned via the command
/// queue and flushed once; then column data is written through the
/// snapshot-ID → local-ID remap built from the component name table.
///
/// Restores instances from the registry's registered sample instances
/// (the component-side mirror of `sampleEvent`). Component types that are
/// needed at spawn time must be registered with a `sample:` instance;
/// restore throws a [StateError] naming the missing type otherwise.
///
/// Returns the mapping of snapshot persistent IDs to newly created entities.
Map<int, Entity> restoreWorldSnapshot(
  final World world,
  final WorldSnapshot snapshot, {
  final Map<String, SnapshotResourceFactory> resourceFactories =
      const <String, SnapshotResourceFactory>{},
  final Map<String, Component Function()> componentFactories =
      const <String, Component Function()>{},
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  registerPersistentId(world);
  world.flush();

  final idRemap = _buildIdRemap(world, snapshot, options);

  // Phase 1: spawn all entities with their structural signatures.
  //
  // Object-tier components spawn as real instances (from componentFactories
  // or the registry's registered sample — the component-side mirror of
  // `sampleEvent`). SoA/tag components are attached as extension pairs:
  // their columns are zero-initialized at spawn and overwritten from column
  // data in Phase 2, so no instance is ever needed.
  final newEntities = <int, Entity>{};
  for (final entry in snapshot.entities) {
    // Idempotency: a persistent id already live in the target world is left
    // untouched, so re-applying the same snapshot is a no-op.
    final existing = _entityWithPersistentId(world, entry.persistentId);
    if (existing != null) {
      newEntities[entry.persistentId] = existing;
      continue;
    }
    final instances = <Component>[PersistentId(entry.persistentId)];
    final extensions = <(Type, Type)>[];
    for (final typeName in entry.components) {
      final localType = _localTypeFor(world, typeName);
      if (localType == null) {
        if (options.strictComponents) {
          throw StateError(
            'Snapshot entity ${entry.persistentId} requires component '
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
    newEntities[entry.persistentId] = world.spawnComponents(
      instances,
      extensions,
    );
  }
  world.flush();

  // Phase 2: write column data onto the freshly spawned entities.
  for (final entry in snapshot.entities) {
    final entity = newEntities[entry.persistentId];
    if (entity == null) continue;
    restoreEntityColumns(
      world,
      entity,
      _remapColumns(entry.columns, idRemap),
      includeOnly: options.includeOnly,
      codecs: options.codecs,
    );
  }

  restoreResourceSnapshot(world, snapshot.resources, resourceFactories);
  return newEntities;
}

Type? _localTypeFor(final World world, final String typeName) {
  for (final entry in world.components.registeredTypes.entries) {
    if (entry.value.toString() == typeName) return entry.value;
  }
  return null;
}

/// Finds the live entity carrying [value], or null.
Entity? _entityWithPersistentId(final World world, final int value) {
  final persistentIdId = _persistentIdComponentIdOrNull(world);
  if (persistentIdId == null) return null;
  for (final archetype in world.archetypes.all) {
    if (!archetype.signature.has(persistentIdId)) continue;
    for (final entity in archetype.entities) {
      final pid = persistentIdOf(world, entity);
      if (pid?.value == value) return entity;
    }
  }
  return null;
}

/// Builds snapshot-ID → local-ID remap from the component name table.
///
/// Resolution uses the target world's registered component types directly,
/// so restoring into a fresh/empty world works without any prior capture.
Map<int, int> _buildIdRemap(
  final World world,
  final WorldSnapshot snapshot,
  final WorldSnapshotOptions options,
) {
  final localTypes = <String, int>{};
  for (final entry in world.components.registeredTypes.entries) {
    localTypes[entry.value.toString()] = entry.key.value;
  }

  final remap = <int, int>{};
  for (final entry in snapshot.componentIds.entries) {
    final localIdValue = localTypes[entry.key];
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
  final Map<String, Object?> columns,
  final Map<int, int> idRemap,
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

String? _componentTypeName(final World world, final ComponentId componentId) {
  try {
    return world.components.getType(componentId).toString();
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}

List<String>? _componentTypeNameOrNull(
  final World world,
  final ComponentId componentId,
) {
  final name = _componentTypeName(world, componentId);
  return name == null ? null : [name];
}

ComponentId? _persistentIdComponentIdOrNull(final World world) =>
    world.components.getComponentIdByType(PersistentId);
