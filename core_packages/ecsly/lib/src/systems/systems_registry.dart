import '../errors/ecs_errors.dart';
import '../plugins/plugin_registry.dart';
import 'schedule.dart';
import 'schedule_id.dart';
import 'schedule_trigger.dart';
import 'system_executor.dart';

/// {@template systems_registry}
/// Central registry for schedules, plugins, and system execution.
///
/// Manages all schedules in a world and provides access to
/// the plugin registry and system executor.
/// {@endtemplate}
class SystemsRegistry {
  /// {@macro systems_registry}
  SystemsRegistry({
    PluginRegistry? plugins,
    SystemExecutor? executor,
  }) : plugins = plugins ?? PluginRegistry(),
       executor = executor ?? const SystemExecutor();

  /// Registry of installed plugins
  final PluginRegistry plugins;

  /// Executor for running systems
  final SystemExecutor executor;

  /// Schedules managed by this registry
  final Map<String, Schedule> _schedules = {};
  List<String>? _schedulesNames;

  /// Get all schedule names.
  List<String> get scheduleNames =>
      _schedulesNames ??= _schedules.keys.toList();

  /// Clear all schedules and plugins.
  void clear() {
    _schedules.clear();
    _schedulesNames = null;
    plugins.clear();
  }

  /// Create a new schedule.
  ///
  /// Throws [EcsStateError] if a schedule with the same id already exists.
  Schedule createSchedule(
    ScheduleId id, {
    ScheduleTrigger? trigger,
  }) {
    final name = id.value;
    if (_schedules.containsKey(name)) {
      throw EcsStateError('Schedule "$name" already exists');
    }

    final schedule = Schedule(
      name,
      trigger: trigger ?? const ManualTrigger(),
      executor: executor,
    );
    _schedules[name] = schedule;
    _schedulesNames = null;
    return schedule;
  }

  /// Get or create a schedule.
  ///
  /// If the schedule exists, returns it. Otherwise, creates a new one.
  Schedule getOrCreateSchedule(
    ScheduleId id, {
    ScheduleTrigger? trigger,
  }) {
    final existing = _schedules[id.value];
    if (existing != null) {
      return existing;
    }
    return createSchedule(id, trigger: trigger);
  }

  /// Get a schedule by id.
  ///
  /// Throws [EcsStateError] if the schedule doesn't exist.
  Schedule getSchedule(ScheduleId id) {
    final schedule = _schedules[id.value];
    if (schedule == null) {
      throw EcsStateError('Schedule "${id.value}" not found');
    }
    return schedule;
  }

  /// Check if a schedule exists.
  bool hasSchedule(ScheduleId id) => _schedules.containsKey(id.value);

  /// Remove a schedule by id.
  ///
  /// Returns true if a schedule was removed, false otherwise.
  bool removeSchedule(ScheduleId id) {
    final removed = _schedules.remove(id.value);
    _schedulesNames = null;
    return removed != null;
  }

  /// Get a schedule by id, or null if it doesn't exist.
  Schedule? tryGetSchedule(ScheduleId id) => _schedules[id.value];
}
