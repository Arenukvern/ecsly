import 'package:ecsly/ecsly.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

import 'mesh_pulse_system.dart';

/// Plugin face of the zone-travel adapter (ADR 0003): registers the mesh
/// sync pulse as an ordinary ecsly system under [meshPulseScheduleId],
/// driven by the game's own scheduler.
///
/// ```dart
/// final session = MeshWorldSession(storage: storage, selfId: peerId);
/// world.addPlugin(WorldZonesPlugin(session, trigger: EveryNSeconds(1)));
/// ```
///
/// The scheduling law stays host-driven (ADR 0003 §1): the plugin never
/// owns a loop — it registers one schedule the game's existing runner
/// (frame loop, host schedule, or a test's `runAsync`) executes like any
/// other. Interest policies ([ZoneCatalogInterest], [SpatialInterestPolicy])
/// remain explicit game-side configuration, not world state.
class WorldZonesPlugin extends Plugin {
  /// Creates the plugin around the world layer's [pulse].
  const WorldZonesPlugin(this.pulse, {this.trigger});

  /// The pulseable world-layer session (e.g. `MeshWorldSession`).
  final Pulseable pulse;

  /// Pulse cadence trigger (default: every 30 seconds, applied at install).
  final ScheduleTrigger? trigger;

  @override
  String get name => 'ecsly_world_zones';

  @override
  void install(final World world) {
    registerMeshPulseSchedule(world, pulse, trigger: trigger);
  }

  @override
  void uninstall(final World world) {
    world.systems.removeSchedule(meshPulseScheduleId);
  }
}
