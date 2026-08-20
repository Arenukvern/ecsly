import 'package:ecsly/ecsly.dart';

import 'schedule_parallel_task_system.dart';

/// Job-system integration extensions on [Schedule].
extension ScheduleExt on Schedule {
  /// Adds a [ScheduleParallelTaskSystem] to this schedule.
  ///
  /// The job system is registered as a system descriptor running [runAsync],
  /// so it participates in dependency ordering via [runAfter] / [runBefore].
  ///
  /// Returns `this` for chaining.
  Schedule addJobSystem(
    final ScheduleParallelTaskSystem jobSystem, {
    required final String name,
    final List<String> runAfter = const [],
    final List<String> runBefore = const [],
  }) => add(
    jobSystem.runAsync,
    name: name,
    runAfter: runAfter,
    runBefore: runBefore,
  );

  /// Adds a job system that runs sequentially after the last added system.
  Schedule thenJobSystem(
    final ScheduleParallelTaskSystem jobSystem, {
    required final String name,
  }) => addJobSystem(
    jobSystem,
    name: name,
    runAfter: lastSystemName != null ? [lastSystemName!] : const [],
  );
}
