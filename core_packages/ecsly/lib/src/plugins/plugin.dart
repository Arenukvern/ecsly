import '../world/world.dart';

/// {@template plugin}
/// A reusable feature bundle that can configure a world with
/// resources, systems, schedules, and other plugins.
///
/// Plugins enable modular, reusable game logic that can be
/// shared across projects.
///
/// Example:
/// ```dart
/// class PhysicsPlugin extends Plugin {
///   @override
///   String get name => 'physics';
///
///   @override
///   void install(World world) {
///     world.resources.push(PhysicsConfig());
///     world.schedule('Update')
///       .add(applyGravitySystem)
///       .then(resolveCollisionsSystem);
///   }
/// }
/// ```
/// {@endtemplate}
abstract class Plugin {
  /// {@macro plugin}
  const Plugin();

  /// Unique name for this plugin
  String get name;

  /// Install this plugin into the world.
  ///
  /// This is where you register resources, add systems to schedules,
  /// create new schedules, and add other plugins.
  void install(final World world);

  /// Optional cleanup when the plugin is removed.
  ///
  /// Override this to remove resources or systems added by this plugin.
  void uninstall(final World world) {}
}
