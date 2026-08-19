import 'package:ecsly/ecsly.dart';

import 'schedule_parallel_task_system.dart';

/// Job system integration into schedule
extension ScheduleExt on Schedule {
  /// Add a certified job system to the schedule.
  Schedule addJobSystem(
    final ScheduleParallelTaskSystem jobSystem, {
    required final String name,
    final List<String> runAfter = const [],
    final List<String> runBefore = const [],
  }) {
    systems.add(
      SystemDescriptor(
        system: jobSystem.runAsync,
        name: name,
        runAfter: runAfter,
        runBefore: runBefore,
      ),
    );
    lastSystemName = name;
    invalidateCache();
    return this;
  }

  /// Add a certified job system sequentially after the last added system.
  Schedule thenJobSystem(
    final ScheduleParallelTaskSystem jobSystem, {
    required final String name,
  }) => addJobSystem(
    jobSystem,
    name: name,
    runAfter: lastSystemName != null ? [lastSystemName!] : const [],
  );
}
