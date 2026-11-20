/// Serialization plugin for [ecsly] worlds.
///
/// Provides JSON snapshot capture and restore for:
/// - Resources implementing [SnapshotableResource];
/// - Entity SoA columns (floats, ints, uint8) via generic column capture;
/// - Whole-world snapshots with a versioned envelope.
///
/// Durable identity is [PersistentEntity] (ADR 0007): allocation via
/// [PersistentEntityAllocator] (sequence default, random for MMO), O(1)
/// resolution via [PersistentEntityIndex], and first-class entity
/// references in the codec contract. Object components require a per-type
/// codec registered in [ObjectComponentCodecRegistry].
library;

export 'src/column_entity_snapshot.dart';
export 'src/component_naming.dart';
export 'src/entity_refs.dart';
export 'src/object_component_codec.dart';
export 'src/persistent_entity.dart';
export 'src/persistent_entity_allocator.dart';
export 'src/persistent_entity_index.dart';
export 'src/resource_snapshot.dart';
export 'src/serialization_plugin.dart';
export 'src/snapshot_migration.dart';
export 'src/world_snapshot.dart';
export 'src/world_snapshot_codec.dart';
