/// Base class for all resources in the ECS world.
///
/// Resources are global singletons that hold state accessible to all systems.
/// Unlike components, resources are not tied to specific entities.
class Resource {}

/// Internal id for [Resource] in the world
///
/// Made to make resource lookups faster and more efficient.
/// Uses integer IDs for O(1) array access instead of Type-based Map lookups.
extension type const ResourceId(int value) {
  /// Zero resource ID (invalid/unset)
  static const ResourceId zero = ResourceId(0);

  /// Maximum resource ID value (supports 256 resources)
  static const int maxValue = 255;

  /// Check if this is a valid resource ID
  bool get isValid => value >= 0 && value <= maxValue;
}
