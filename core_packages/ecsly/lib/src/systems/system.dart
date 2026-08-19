import '../world/world.dart';

/// {@template async_system}
/// An asynchronous system that operates on the world state.
///
/// Async systems can perform I/O operations, await futures,
/// and are executed sequentially or in parallel based on configuration.
///
/// Example:
/// ```dart
/// Future<void> loadAssetsSystem(World world) async {
///   final assets = await loadFromDisk();
///   world.resources.push(assets);
/// }
/// ```
/// {@endtemplate}
typedef AsyncSystem = Future<void> Function(World world);

/// {@template system}
/// A system is a function that operates on the world state.
///
/// Systems can be either sync or async, and can be composed
/// into schedules for organized execution.
///
/// Example:
/// ```dart
/// void movementSystem(World world) {
///   for (final (entity, pos, vel) in world.query2<Position, Velocity>()) {
///     // Update positions based on velocity
///   }
/// }
/// ```
/// {@endtemplate}
typedef System = void Function(World world);

/// {@template execution_mode}
/// Defines how a system should be executed.
/// {@endtemplate}
enum ExecutionMode {
  /// Execute synchronously in the main thread
  sync,

  /// Execute asynchronously, awaiting completion
  async,

  /// Execute asynchronously in parallel with other parallel systems
  asyncParallel,
}
