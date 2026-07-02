import '../world/world.dart';

/// Optional observer for flush boundaries.
///
/// Default is "off" (null observer). Intended for debugging/telemetry.
abstract interface class WorldFlushObserver {
  void onFlushEnd(
    final World world, {
    required final int elapsedMicroseconds,
    required final int commandsExecuted,
    required final int resourcesPushed,
    required final int resourcesRemoved,
  });

  void onFlushStart(final World world);
}

/// No-op base to simplify implementations.
class WorldFlushObserverBase implements WorldFlushObserver {
  const WorldFlushObserverBase();

  @override
  void onFlushEnd(
    final World world, {
    required final int elapsedMicroseconds,
    required final int commandsExecuted,
    required final int resourcesPushed,
    required final int resourcesRemoved,
  }) {}

  @override
  void onFlushStart(final World world) {}
}
