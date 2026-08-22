import 'package:ecsly/ecsly.dart';

import 'column_entity_snapshot.dart';
import 'object_component_codec.dart';
import 'resource_snapshot.dart';

/// Version of the world snapshot envelope.
const int worldSnapshotVersion = 1;

/// A full snapshot of a world: resources plus all live entities with their
/// column data.
class WorldSnapshot {
  /// Creates a world snapshot.
  const WorldSnapshot({
    required this.version,
    required this.resources,
    required this.entities,
  });

  /// Envelope format version.
  final int version;

  /// Resource snapshot keyed by resource type name.
  final Map<String, Object?> resources;

  /// Per-entity snapshots: entity index, generation, and column data.
  final List<EntitySnapshotEntry> entities;

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'resources': resources,
    'entities': entities.map((final e) => e.toJson()).toList(growable: false),
  };

  /// Deserializes from a JSON-compatible map.
  // ignore: prefer_constructors_over_static_methods
  static WorldSnapshot fromJson(final Map<String, Object?> json) =>
      WorldSnapshot(
        version: (json['version'] as num?)?.toInt() ?? worldSnapshotVersion,
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
  const WorldSnapshotOptions({this.fieldNames, this.includeOnly, this.codecs});

  /// Human-readable key names per component ID.
  final Map<ComponentId, List<String>>? fieldNames;

  /// Restrict capture/restore to these component IDs.
  final Set<ComponentId>? includeOnly;

  /// Codecs for object-tier components.
  final ObjectComponentCodecRegistry? codecs;
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
    resources: captureResourceSnapshot(world),
    entities: entities,
  );
}

/// Restores a [WorldSnapshot] into a fresh [world].
///
/// Entities are re-created with their original index/generation when
/// possible; column data is written back via [restoreEntityColumns].
/// Resources are restored via [resourceFactories].
///
/// The target world must have the same component types registered in the
/// same registration order as the world the snapshot came from — component
/// IDs are world-local and positional.
void restoreWorldSnapshot(
  final World world,
  final WorldSnapshot snapshot, {
  final Map<String, SnapshotResourceFactory> resourceFactories =
      const <String, SnapshotResourceFactory>{},
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  world.flush();

  for (final entry in snapshot.entities) {
    final entity = Entity.create(entry.index, entry.generation);
    if (!world.entities.isAlive(entity)) continue;
    restoreEntityColumns(
      world,
      entity,
      entry.columns,
      fieldNames: options.fieldNames,
      includeOnly: options.includeOnly,
      codecs: options.codecs,
    );
  }

  restoreResourceSnapshot(world, snapshot.resources, resourceFactories);
}
