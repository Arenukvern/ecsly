import '../../../resources/resource.dart';

/// Resource tracking spawn/despawn performance metrics.
///
/// Tracks timing for spawn, despawn, and flush operations,
/// as well as command queue status and entity counts.
class SpawnPerformanceResource extends Resource {
  SpawnPerformanceResource({
    required this.spawnTimeMs,
    required this.despawnTimeMs,
    required this.flushTimeMs,
    required this.commandsQueued,
    required this.entitiesSpawned,
    required this.entitiesDespawned,
  });

  double spawnTimeMs;
  double despawnTimeMs;
  double flushTimeMs;
  int commandsQueued;
  int entitiesSpawned;
  int entitiesDespawned;

  void update({
    required double spawnTimeMs,
    required double despawnTimeMs,
    required double flushTimeMs,
    required int commandsQueued,
    required int entitiesSpawned,
    required int entitiesDespawned,
  }) {
    this.spawnTimeMs = spawnTimeMs;
    this.despawnTimeMs = despawnTimeMs;
    this.flushTimeMs = flushTimeMs;
    this.commandsQueued = commandsQueued;
    this.entitiesSpawned = entitiesSpawned;
    this.entitiesDespawned = entitiesDespawned;
  }
}
