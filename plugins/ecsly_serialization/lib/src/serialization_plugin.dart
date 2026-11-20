import 'package:ecsly/ecsly.dart';

import 'persistent_entity.dart';
import 'persistent_entity_allocator.dart';
import 'persistent_entity_index.dart';
import 'resource_snapshot.dart';
import 'world_snapshot.dart';

/// Resource holding the serialization configuration in the world.
class SerializationConfigResource extends Resource {
  /// Creates the config resource.
  SerializationConfigResource({
    this.config = const WorldSnapshotOptions(),
    this.resourceFactories = const <String, SnapshotResourceFactory>{},
  });

  /// Options controlling capture and restore behavior.
  final WorldSnapshotOptions config;

  /// Factories used to restore snapshotable resources (legacy,
  /// resolver-less path). Prefer a [SnapshotResourceRegistry].
  final Map<String, SnapshotResourceFactory> resourceFactories;
}

/// Plugin that makes world serialization native to the ECS.
///
/// Registers [SerializationConfigResource] so systems and tools can capture
/// and restore snapshots without external wiring.
///
/// With [manageIds] (default false), install also upserts the durable
/// identity layer (ADR 0007): [PersistentEntityAllocatorResource] wrapping
/// [allocator] (a [SequencePersistentEntityAllocator] by default) and the
/// [PersistentEntityIndex]. Restore then auto-adopts allocation state, and
/// `world.spawnPersistent(...)` becomes the one allocation path.
///
/// Usage:
/// ```dart
/// world.addPlugin(SerializationPlugin(
///   options: WorldSnapshotOptions(codecs: myCodecs),
///   manageIds: true,
/// ));
/// ```
class SerializationPlugin extends Plugin {
  /// Creates the plugin with capture/restore [options], resource factories,
  /// and optional identity management.
  const SerializationPlugin({
    this.options = const WorldSnapshotOptions(),
    this.resourceFactories = const <String, SnapshotResourceFactory>{},
    this.manageIds = false,
    this.allocator,
  });

  /// Options controlling capture and restore behavior.
  final WorldSnapshotOptions options;

  /// Factories used to restore snapshotable resources (legacy,
  /// resolver-less path). Prefer a [SnapshotResourceRegistry].
  final Map<String, SnapshotResourceFactory> resourceFactories;

  /// Whether install upserts the durable identity layer
  /// (allocator + index).
  final bool manageIds;

  /// The allocator policy to install with [manageIds]; defaults to a
  /// [SequencePersistentEntityAllocator] (deterministic, replay-safe).
  final PersistentEntityAllocator? allocator;

  @override
  String get name => 'ecsly_serialization';

  @override
  void install(World world) {
    world.upsertResource(
      SerializationConfigResource(
        config: options,
        resourceFactories: resourceFactories,
      ),
    );
    if (manageIds) {
      registerPersistentEntity(world);
      world
        ..upsertResource(
          PersistentEntityAllocatorResource(
            allocator ?? SequencePersistentEntityAllocator(),
          ),
        )
        ..upsertResource(PersistentEntityIndex());
    }
  }

  @override
  void uninstall(World world) {
    world.resources.remove<SerializationConfigResource>();
    if (manageIds) {
      world.resources
        ..remove<PersistentEntityAllocatorResource>()
        ..remove<PersistentEntityIndex>();
    }
  }
}
