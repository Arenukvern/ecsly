import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'plugin.dart';

/// {@template plugin_registry}
/// Registry for managing installed plugins.
///
/// Tracks which plugins are installed and prevents duplicate installations.
/// {@endtemplate}
class PluginRegistry {
  /// {@macro plugin_registry}
  PluginRegistry();

  /// name: plugin
  final Map<String, Plugin> _plugins = {};

  /// Get all installed plugin names.
  Iterable<String> get names => _plugins.keys;

  /// Add a plugin to the world.
  ///
  /// Throws [PluginInstallationException] if a plugin with the same name is already installed.
  void add(final Plugin plugin, final World world) {
    if (_plugins.containsKey(plugin.name)) {
      throw PluginInstallationException(
        plugin.name,
        'Plugin with the same name is already installed',
      );
    }

    plugin.install(world);
    _plugins[plugin.name] = plugin;
  }

  /// Clear all plugins.
  ///
  /// Note: This does not call uninstall on plugins.
  void clear() => _plugins.clear();

  /// Get a plugin by name.
  ///
  /// Returns null if the plugin is not installed.
  Plugin? get(final String name) => _plugins[name];

  /// Check if a plugin is installed.
  bool has(final String name) => _plugins.containsKey(name);

  /// Remove a plugin from the world.
  ///
  /// Calls the plugin's uninstall method if it exists.
  /// Returns true if a plugin was removed, false otherwise.
  bool remove(final String name, final World world) {
    final plugin = _plugins.remove(name);
    if (plugin != null) {
      plugin.uninstall(world);
      return true;
    }
    return false;
  }
}
