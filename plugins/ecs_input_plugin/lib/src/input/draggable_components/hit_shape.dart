/// Hit shape configuration for interactive elements.
///
/// Extends InteractiveElement to support different hit testing shapes
/// while maintaining backward compatibility with circular hit testing.
class HitShape {
  /// Creates a circular hit shape.
  const HitShape.circle(this.radius)
    : type = HitShapeType.circle,
      width = null,
      height = null;

  /// Creates a rectangular hit shape.
  const HitShape.rectangle({required this.width, required this.height})
    : type = HitShapeType.rectangle,
      radius = null;

  /// The shape type.
  final HitShapeType type;

  /// Radius for circular hit testing (null for rectangle).
  final double? radius;

  /// Width for rectangular hit testing (null for circle).
  final double? width;

  /// Height for rectangular hit testing (null for circle).
  final double? height;
}

/// Hit shape types for interactive elements.
enum HitShapeType {
  /// Circular hit area (default, uses hitRadius).
  circle,

  /// Rectangular/AABB hit area (uses hitWidth and hitHeight).
  rectangle,
}
