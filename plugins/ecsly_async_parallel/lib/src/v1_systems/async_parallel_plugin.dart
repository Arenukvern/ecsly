import 'package:ecsly/ecsly.dart';

import 'resource.dart';

/// {@template async_parallel_plugin}
/// Installs the resources required by job systems into a world.
///
/// Job systems depend on [ScheduleJobResultQueueResource] to track in-flight
/// work and merge best-effort results across frames. The core `World`
/// constructor installs [ScheduleExecutionPolicyResource] (it owns the enum and
/// the policy), but the result queue was moved out of the core into this
/// plugin — so it must be installed explicitly.
///
/// Install this plugin alongside any job-system-using plugin (for example
/// [ECSCollisionPlugin] in `ecs_collision_plugins`) before the first frame:
///
/// ```dart
/// world.addPlugin(AsyncParallelPlugin());
/// world.addPlugin(ECSCollisionPlugin(...));
/// ```
/// {@endtemplate}
class AsyncParallelPlugin extends Plugin {
  /// {@macro async_parallel_plugin}
  const AsyncParallelPlugin();

  @override
  String get name => 'ecsly_async_parallel';

  @override
  void install(final World world) {
    if (!world.resources.has<ScheduleJobResultQueueResource>()) {
      world.upsertResource(ScheduleJobResultQueueResource());
    }
  }
}
