import '../world/world.dart';
import 'system_descriptor.dart';

/// Optional, low-overhead observer for schedule/system execution.
///
/// Default is "off" (null observer). When enabled, implementations should
/// avoid allocations on hot paths (use intern tables, typed buffers, etc.).
abstract interface class EcsExecutionObserver {
  void onScheduleEnd(final World world, final String scheduleName);

  void onScheduleStart(
    final World world,
    final String scheduleName, {
    required final int systemCount,
  });

  void onSystemEnd(
    final World world,
    final String scheduleName,
    final SystemDescriptor system, {
    required final int elapsedMicroseconds,
    final Object? error,
    final StackTrace? stackTrace,
  });

  void onSystemStart(
    final World world,
    final String scheduleName,
    final SystemDescriptor system,
  );
}

/// No-op base to simplify implementations.
class EcsExecutionObserverBase implements EcsExecutionObserver {
  const EcsExecutionObserverBase();

  @override
  void onScheduleEnd(final World world, final String scheduleName) {}

  @override
  void onScheduleStart(
    final World world,
    final String scheduleName, {
    required final int systemCount,
  }) {}

  @override
  void onSystemEnd(
    final World world,
    final String scheduleName,
    final SystemDescriptor system, {
    required final int elapsedMicroseconds,
    final Object? error,
    final StackTrace? stackTrace,
  }) {}

  @override
  void onSystemStart(
    final World world,
    final String scheduleName,
    final SystemDescriptor system,
  ) {}
}
