import '../world/world.dart';
import 'system_descriptor.dart';

/// Optional, low-overhead observer for schedule/system execution.
///
/// Default is "off" (null observer). When enabled, implementations should
/// avoid allocations on hot paths (use intern tables, typed buffers, etc.).
abstract interface class EcsExecutionObserver {
  void onScheduleEnd(World world, String scheduleName);

  void onScheduleStart(
    World world,
    String scheduleName, {
    required int systemCount,
  });

  void onSystemEnd(
    World world,
    String scheduleName,
    SystemDescriptor system, {
    required int elapsedMicroseconds,
    Object? error,
    StackTrace? stackTrace,
  });

  void onSystemStart(
    World world,
    String scheduleName,
    SystemDescriptor system,
  );
}

/// No-op base to simplify implementations.
class EcsExecutionObserverBase implements EcsExecutionObserver {
  const EcsExecutionObserverBase();

  @override
  void onScheduleEnd(World world, String scheduleName) {}

  @override
  void onScheduleStart(
    World world,
    String scheduleName, {
    required int systemCount,
  }) {}

  @override
  void onSystemEnd(
    World world,
    String scheduleName,
    SystemDescriptor system, {
    required int elapsedMicroseconds,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void onSystemStart(
    World world,
    String scheduleName,
    SystemDescriptor system,
  ) {}
}
