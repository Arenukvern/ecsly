import '../errors/ecs_errors.dart';
import '../events/events.dart';
import '../resources/resources.dart';
import '../world/world.dart';

double _resolveCurrentSeconds(final World world) {
  if (world.resources.has<ScheduleTimeResource>()) {
    return world.getResource<ScheduleTimeResource>().elapsedSeconds;
  }

  if (world.resources.has<WallClockScheduleTimeResource>()) {
    return world.getResource<WallClockScheduleTimeResource>().nowSeconds;
  }

  throw ScheduleTimeSourceMissingError();
}

double _resolveDeltaSeconds(final World world) {
  if (world.resources.has<ScheduleTimeResource>()) {
    return world.getResource<ScheduleTimeResource>().deltaSeconds;
  }

  if (world.resources.has<DeltaTimeResource>()) {
    return world.getResource<DeltaTimeResource>().deltaTime;
  }

  if (world.resources.has<WallClockScheduleTimeResource>()) {
    final clock = world.getResource<WallClockScheduleTimeResource>();
    final delta = clock.nowSeconds - clock.lastTickSeconds;
    clock.lastTickSeconds = clock.nowSeconds;
    return delta;
  }
  throw ScheduleTimeSourceMissingError();
}

/// {@template condition_trigger}
/// Trigger based on a custom condition function.
///
/// Example:
/// ```dart
/// ConditionTrigger((world) => world.resource<GameTime>().isPaused == false)
/// ```
/// {@endtemplate}
class ConditionTrigger extends ScheduleTrigger {
  /// {@macro condition_trigger}
  const ConditionTrigger(this.condition);

  /// The condition function to evaluate
  final bool Function(World world) condition;

  @override
  bool shouldRun(final World world) => condition(world);
}

/// {@template event_trigger}
/// Trigger that runs only when events exist in a channel.
///
/// This trigger checks if the specified event channel has any events.
/// If events are present, the schedule executes. If not, the schedule
/// is skipped, providing efficient event-driven execution.
///
/// The event channel must be explicitly registered before use.
/// Throws [EventTriggerValidationError] if the channel is not registered.
///
/// Example:
/// ```dart
/// // Register channel first
/// world.events.register<DamageEvent>();
///
/// // Only run when damage events exist
/// world.createSchedule(
///   'DamageHandler',
///   trigger: EventTrigger<DamageEvent>(),
/// )
///   .add(processDamageSystem)
///   .then(eventClearSystem);
///
/// // Can combine with throttling for rate limiting
/// world.createSchedule(
///   'InputHandler',
///   trigger: ThrottledTrigger(
///     EventTrigger<InputEvent>(),
///     minIntervalSeconds: 0.016, // Max 60 FPS
///   ),
/// );
/// ```
/// {@endtemplate}
class EventTrigger<T extends EcsEvent> extends ScheduleTrigger {
  /// {@macro event_trigger}
  const EventTrigger();

  @override
  bool shouldRun(final World world) {
    try {
      return world.events.reader<T>().isNotEmpty;
    } on EventNotRegisteredException {
      // Convert to more specific error for EventTrigger usage
      throw EventTriggerValidationError(T);
    }
  }
}

/// {@template every_frame}
/// Trigger that runs every frame.
/// {@endtemplate}
class EveryFrame extends ScheduleTrigger {
  /// {@macro every_frame}
  const EveryFrame();

  @override
  bool shouldRun(final World world) => true;
}

/// {@template every_n_frames}
/// Trigger that runs every N frames.
/// {@endtemplate}
class EveryNFrames extends ScheduleTrigger {
  /// {@macro every_n_frames}
  EveryNFrames(this.n) : _counter = 0;

  /// Number of frames between executions
  final int n;

  int _counter;

  @override
  bool shouldRun(final World world) {
    _counter++;
    if (_counter >= n) {
      _counter = 0;
      return true;
    }
    return false;
  }
}

/// {@template every_n_seconds}
/// Trigger that runs every N seconds based on time accumulation.
///
/// Attempts to use a resource with a `deltaTime` property (typically
/// [DeltaTimeResource]) for frame-rate independent timing. Falls back to
/// system time if deltaTime resource is not available.
///
/// Example:
/// ```dart
/// EveryNSeconds(0.3) // Run every 300ms
/// EveryNSeconds(2.0) // Run every 2 seconds
/// ```
/// {@endtemplate}
class EveryNSeconds extends ScheduleTrigger {
  /// {@macro every_n_seconds}
  EveryNSeconds(this.intervalSeconds) : _accumulatedTime = 0.0;

  /// Time interval in seconds between executions
  final double intervalSeconds;

  double _accumulatedTime;

  @override
  bool shouldRun(final World world) {
    final deltaSeconds = _resolveDeltaSeconds(world);
    _accumulatedTime += deltaSeconds;
    if (_accumulatedTime >= intervalSeconds) {
      _accumulatedTime -= intervalSeconds;
      return true;
    }
    return false;
  }
}

/// {@template manual_trigger}
/// Trigger that only runs when manually invoked.
///
/// This is the default for schedules without explicit triggers.
/// {@endtemplate}
class ManualTrigger extends ScheduleTrigger {
  /// {@macro manual_trigger}
  const ManualTrigger();

  @override
  bool shouldRun(final World world) => true;
}

/// {@template schedule_trigger}
/// Determines when a schedule should execute.
///
/// Triggers can be frame-based, time-based, event-based, or custom.
/// Use [ThrottledTrigger] to prevent CPU overload from tight loops.
/// {@endtemplate}
sealed class ScheduleTrigger {
  /// {@macro schedule_trigger}
  const ScheduleTrigger();

  /// Check if the schedule should run
  bool shouldRun(final World world);
}

/// {@template throttled_trigger}
/// Wrapper trigger that limits execution frequency to prevent CPU overload.
///
/// Throttles a base trigger to ensure it doesn't execute more than once
/// per specified duration (in seconds). Useful for preventing tight loops
/// when using EveryFrame or frequently-triggering ConditionTrigger.
///
/// Example:
/// ```dart
/// ThrottledTrigger(
///   EveryFrame(),
///   minIntervalSeconds: 0.016, // Max 60 FPS
/// )
/// ```
/// {@endtemplate}
class ThrottledTrigger extends ScheduleTrigger {
  /// {@macro throttled_trigger}
  ThrottledTrigger(this.baseTrigger, {required this.minIntervalSeconds})
    : _lastExecutionTime = 0;

  /// The base trigger to throttle
  final ScheduleTrigger baseTrigger;

  /// Minimum time (in seconds) between executions
  final double minIntervalSeconds;

  double _lastExecutionTime;

  @override
  bool shouldRun(final World world) {
    final currentTime = _resolveCurrentSeconds(world);

    if (currentTime - _lastExecutionTime < minIntervalSeconds) {
      return false;
    }

    if (baseTrigger.shouldRun(world)) {
      _lastExecutionTime = currentTime;
      return true;
    }

    return false;
  }
}
