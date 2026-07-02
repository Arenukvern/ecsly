import '../world/world.dart';

/// {@template flush_all_system}
/// Convenience system that runs all flush phases in the correct order.
///
/// Executes phases in order: entities → components → resources → commands.
/// Each phase only executes if it has pending changes (conditional flushing).
///
/// Delegates to [World.flush] to ensure consistent behavior, safety guards,
/// and proper exception handling.
///
/// Example:
/// ```dart
/// schedule.add(flushAllSystem, name: 'flushAll');
/// ```
/// {@endtemplate}
void flushAllSystem(final World world) {
  // Delegate to World.flush() for consistency, safety guards, and proper
  // exception handling. This ensures isFlushing guard is set, try/finally
  // wrapper is used, and second-flush logic is consistent.
  world.flush();
}

/// {@template flush_commands_system}
/// System that executes the command queue.
///
/// Only executes if commands are pending (conditional flushing).
/// Can be scheduled like any other system with dependencies and ordering.
///
/// **Note**: This system checks `isFlushing` to prevent recursive flush cycles.
/// If already flushing, this system does nothing (flush will happen at the
/// end of the current flush operation).
///
/// Example:
/// ```dart
/// schedule.add(flushCommandsSystem, name: 'flushCommands');
/// ```
/// {@endtemplate}
void flushCommandsSystem(final World world) {
  // Prevent recursive flushing during command execution
  if (world.isFlushing) return;
  world.flushCommandsOnly();
}

/// {@template flush_components_system}
/// System that flushes the component registry.
///
/// **Note**: Components are stored in archetypes and don't have a pending queue.
/// Component changes are processed via the command queue. This system is
/// kept for API consistency but is effectively a no-op.
///
/// Can be scheduled like any other system with dependencies and ordering.
/// Checks `isFlushing` to prevent recursive flush cycles.
///
/// Example:
/// ```dart
/// schedule.add(flushComponentsSystem, name: 'flushComponents');
/// ```
/// {@endtemplate}
void flushComponentsSystem(final World world) {
  // Prevent recursive flushing during command execution
  if (world.isFlushing) return;
  world.flushComponentsOnly();
}

/// {@template flush_entities_system}
/// System that flushes the entity registry.
///
/// **Note**: Entities don't have a pending queue - they're managed directly.
/// Entity changes are processed via the command queue. This system is
/// kept for API consistency but is effectively a no-op.
///
/// Can be scheduled like any other system with dependencies and ordering.
/// Checks `isFlushing` to prevent recursive flush cycles.
///
/// Example:
/// ```dart
/// schedule.add(flushEntitiesSystem, name: 'flushEntities');
/// ```
/// {@endtemplate}
void flushEntitiesSystem(final World world) {
  // Prevent recursive flushing during command execution
  if (world.isFlushing) return;
  world.flushEntitiesOnly();
}

/// {@template flush_resources_system}
/// System that flushes the resource registry.
///
/// Only executes if resources have pending changes (conditional flushing).
/// Can be scheduled like any other system with dependencies and ordering.
///
/// **Note**: This system checks `isFlushing` to prevent recursive flush cycles.
/// If already flushing, this system does nothing (flush will happen at the
/// end of the current flush operation).
///
/// Example:
/// ```dart
/// schedule.add(flushResourcesSystem, name: 'flushResources');
/// ```
/// {@endtemplate}
void flushResourcesSystem(final World world) {
  // Prevent recursive flushing during command execution
  if (world.isFlushing) return;
  world.flushResourcesOnly();
}
