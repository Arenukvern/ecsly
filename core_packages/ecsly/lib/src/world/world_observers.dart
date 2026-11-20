import '../world/world.dart';

/// Optional observer for flush boundaries.
///
/// Default is "off" (null observer). Intended for debugging/telemetry.
abstract interface class WorldFlushObserver {
  void onFlushEnd(
    World world, {
    required int elapsedMicroseconds,
    required int commandsExecuted,
    required int resourcesPushed,
    required int resourcesRemoved,
  });

  void onFlushStart(World world);
}

/// No-op base to simplify implementations.
class WorldFlushObserverBase implements WorldFlushObserver {
  const WorldFlushObserverBase();

  @override
  void onFlushEnd(
    World world, {
    required int elapsedMicroseconds,
    required int commandsExecuted,
    required int resourcesPushed,
    required int resourcesRemoved,
  }) {}

  @override
  void onFlushStart(World world) {}
}
