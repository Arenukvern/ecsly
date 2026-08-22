import 'package:ecsly/ecsly.dart';

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

  /// Factories used to restore snapshotable resources.
  final Map<String, SnapshotResourceFactory> resourceFactories;
}

/// Plugin that makes world serialization native to the ECS.
///
/// Registers [SerializationConfigResource] so systems and tools can capture
/// and restore snapshots without external wiring.
///
/// Usage:
/// ```dart
/// world.addPlugin(SerializationPlugin(
///   options: WorldSnapshotOptions(codecs: myCodecs),
/// ));
/// ```
class SerializationPlugin extends Plugin {
  /// Creates the plugin with capture/restore [options] and resource factories.
  const SerializationPlugin({
    this.options = const WorldSnapshotOptions(),
    this.resourceFactories = const <String, SnapshotResourceFactory>{},
  });

  /// Options controlling capture and restore behavior.
  final WorldSnapshotOptions options;

  /// Factories used to restore snapshotable resources.
  final Map<String, SnapshotResourceFactory> resourceFactories;

  @override
  String get name => 'ecsly_serialization';

  @override
  void install(final World world) {
    world.upsertResource(
      SerializationConfigResource(
        config: options,
        resourceFactories: resourceFactories,
      ),
    );
  }

  @override
  void uninstall(final World world) {
    world.resources.remove<SerializationConfigResource>();
  }
}
