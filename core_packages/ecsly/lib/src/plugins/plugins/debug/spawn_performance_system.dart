import 'dart:developer' as developer;

import '../../../systems/systems.dart';
import '../../../world/world.dart';
import 'spawn_performance_resource.dart';

/// Flush system with timing instrumentation
void flushAllWithTimingSystem(final World world) {
  final stopwatch = Stopwatch()..start();
  developer.Timeline.startSync('flush');

  final commandsBefore = world.commandQueue.needsFlush;

  flushAllSystem(world);

  stopwatch.stop();
  final flushTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
  developer.Timeline.finishSync();

  // Update spawn performance metrics - direct mutation
  final spawnPerf = world.getResource<SpawnPerformanceResource>();
  final commandsAfter = world.commandQueue.needsFlush;
  spawnPerf.update(
    spawnTimeMs: spawnPerf.spawnTimeMs,
    despawnTimeMs: spawnPerf.despawnTimeMs,
    flushTimeMs: flushTimeMs,
    commandsQueued: commandsAfter ? 1 : 0,
    entitiesSpawned: spawnPerf.entitiesSpawned,
    entitiesDespawned: spawnPerf.entitiesDespawned,
  );

  developer.Timeline.instantSync(
    'flush_all',
    arguments: {
      'timeMs': flushTimeMs,
      'commandsBefore': commandsBefore,
      'commandsAfter': commandsAfter,
    },
  );
}
