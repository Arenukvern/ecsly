/// Should be strictly serializable / deserializable data
/// No logic.
class Component {
  const Component();
}

/// Internal id for [Component] in the world
///
/// Made to make the searches faster and more efficient.
/// Uses integer IDs (0-255) for O(1) bitmask operations.
extension type const ComponentId(int value) {
  /// Zero component ID (invalid/unset)
  static const ComponentId zero = ComponentId(0);

  /// Maximum component ID value (supports 256 components)
  static const int maxValue = 255;

  /// Check if this is a valid component ID
  bool get isValid => value >= 0 && value <= maxValue;
}
