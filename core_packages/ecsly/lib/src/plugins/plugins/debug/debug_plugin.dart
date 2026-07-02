// ignore_for_file: cascade_invocations

import '../../../plugins/plugin.dart';
import '../../../systems/schedule_trigger.dart';
import '../../../world/world.dart';
import 'performance_resource.dart';
import 'performance_system.dart';
import 'spawn_performance_resource.dart';
import 'spawn_performance_system.dart';

/// Debug plugin providing performance monitoring and metrics.
///
/// Registers [PerformanceResource] and [SpawnPerformanceResource],
/// and adds [performanceSystem] to the 'Update' schedule (or creates it if missing).
///
/// Example:
/// ```dart
/// world.plugins.add(DebugPlugin(), world);
/// ```
class DebugPlugin extends Plugin {
  /// System name used when adding performanceSystem to schedule
  static const String _performanceSystemName = 'debug_performance';
  static const String _flushAllWithTimingSystemName =
      'debug_flushAllWithTiming';
  static const String _scheduleName = 'HighFrequency';

  @override
  String get name => 'debug';

  @override
  void install(final World world) {
    // Register performance resources with default values
    world.resources.push(
      PerformanceResource(fps: 0, frameTime: 0, entityCount: 0),
    );
    world.resources.push(
      SpawnPerformanceResource(
        spawnTimeMs: 0,
        despawnTimeMs: 0,
        flushTimeMs: 0,
        commandsQueued: 0,
        entitiesSpawned: 0,
        entitiesDespawned: 0,
      ),
    );

    // Add performance system to HighFrequency schedule (preferred for games),
    // create it if it doesn't exist
    world
        .getOrCreateSchedule(_scheduleName, trigger: const EveryFrame())
        .add(performanceSystem, name: _performanceSystemName)
        .add(flushAllWithTimingSystem, name: _flushAllWithTimingSystemName);
  }

  @override
  void uninstall(final World world) {
    // Remove performance system from schedule (try HighFrequency first, then Update)
    if (world.hasSchedule(_scheduleName)) {
      final schedule = world.schedule(_scheduleName);
      schedule.removeSystem(_performanceSystemName);
      schedule.removeSystem(_flushAllWithTimingSystemName);
    }

    // Remove resources
    world.resources.remove<PerformanceResource>();
    world.resources.remove<SpawnPerformanceResource>();
  }
}
