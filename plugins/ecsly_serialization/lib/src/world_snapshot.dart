import 'package:ecsly/ecsly.dart';

import 'column_entity_snapshot.dart';
import 'object_component_codec.dart';
import 'resource_snapshot.dart';

/// Version of the world snapshot envelope format.
const int worldSnapshotVersion = 2;

/// A full snapshot of a world: resources plus all live entities with their
/// column data.
///
/// The snapshot records a component name table ([componentIds]) mapping
/// component type names to the source world's local `ComponentId`s. Restore
/// uses this table to remap data onto the target world's own IDs, so
/// snapshots survive registration reordering, additions, and removals.
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
  /// IDs stay world-local.
  final Map<String, int> componentIds;

  /// Resource snapshot keyed by resource type name.
  final Map<String, Object?> resources;

  /// Per-entity snapshots: entity index, generation, and column data.
  final List<EntitySnapshotEntry> entities;

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
            .map(EntitySnapshotEntry.fromJson)
            .toList(growable: false),
      );
}

/// Serialized state of a single entity.
class EntitySnapshotEntry {
  /// Creates an entity snapshot entry.
  const EntitySnapshotEntry({
    required this.index,
    required this.generation,
    required this.columns,
  });

  /// Entity index (lower 32 bits of the packed id).
  final int index;

  /// Entity generation (upper 32 bits of the packed id).
  final int generation;

  /// Flat column data for this entity.
  final Map<String, Object?> columns;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'generation': generation,
    'columns': columns,
  };

  /// Deserializes from a JSON-compatible map.
  // ignore: prefer_constructors_over_static_methods
  static EntitySnapshotEntry fromJson(final Map<String, Object?> json) =>
      EntitySnapshotEntry(
        index: (json['index'] as num?)?.toInt() ?? 0,
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        columns: (json['columns'] as Map? ?? const {}).map(
          (final k, final v) => MapEntry(k.toString(), v),
        ),
      );
}

/// Options controlling whole-world capture and restore.
class WorldSnapshotOptions {
  /// Creates snapshot options.
  const WorldSnapshotOptions({
    this.fieldNames,
    this.includeOnly,
    this.codecs,
    this.schemaVersion = 1,
    this.strictComponents = false,
  });

  /// Human-readable key names per component ID.
  final Map<ComponentId, List<String>>? fieldNames;

  /// Restrict capture/restore to these component IDs.
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
/// The world is flushed first so pending commands and resource pushes are
/// reflected in the snapshot.
WorldSnapshot captureWorldSnapshot(
  final World world, {
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  world.flush();

  final componentIds = <String, int>{};
  for (final archetype in world.archetypes.all) {
    for (final componentId in archetype.componentIds) {
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

  final entities = <EntitySnapshotEntry>[];
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      final columns = captureEntityColumns(
        world,
        entity,
        fieldNames: options.fieldNames,
        includeOnly: options.includeOnly,
        codecs: options.codecs,
      );
      if (columns == null) continue;
      entities.add(
        EntitySnapshotEntry(
          index: entity.indexValue,
          generation: entity.generation.value,
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

/// Restores a [WorldSnapshot] into [world].
///
/// Component data keys in the snapshot refer to the *source* world's
/// component IDs. Restore resolves them through the snapshot's component
/// name table onto the target world's own IDs, so the target world may have
/// a different registration order or additional/missing component types.
///
/// Entities must already exist in the target world (state, not structure, is
/// serialized). Resources are restored via [resourceFactories].
void restoreWorldSnapshot(
  final World world,
  final WorldSnapshot snapshot, {
  final Map<String, SnapshotResourceFactory> resourceFactories =
      const <String, SnapshotResourceFactory>{},
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  world.flush();

  final idRemap = _buildIdRemap(world, snapshot, options);

  for (final entry in snapshot.entities) {
    final entity = Entity.create(entry.index, entry.generation);
    if (!world.entities.isAlive(entity)) continue;
    restoreEntityColumns(
      world,
      entity,
      _remapColumns(entry.columns, idRemap),
      fieldNames: options.fieldNames,
      includeOnly: options.includeOnly,
      codecs: options.codecs,
    );
  }

  restoreResourceSnapshot(world, snapshot.resources, resourceFactories);
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
      // Named key (fieldNames) — pass through untouched.
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
