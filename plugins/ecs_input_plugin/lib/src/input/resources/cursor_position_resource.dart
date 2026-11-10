import 'package:ecsly/ecsly.dart';

/// Resource for tracking cursor position in world coordinates.
///
/// Used for cursor tracking during drag interactions and for visual feedback
/// like brush boundaries or hover effects.
class CursorPositionResource extends Resource {
  CursorPositionResource();

  /// Current cursor X position in world coordinates (null if not hovering)
  double? worldX;

  /// Current cursor Y position in world coordinates (null if not hovering)
  double? worldY;

  /// Whether the cursor is currently hovering over the interaction area
  bool isHovering = false;

  /// Update cursor position from screen coordinates.
  ///
  /// [worldX] World X coordinate
  /// [worldY] World Y coordinate
  /// [isHovering] Whether cursor is hovering
  void updatePosition({
    required final bool isHovering,
    final double? worldX,
    final double? worldY,
  }) {
    this.worldX = worldX;
    this.worldY = worldY;
    this.isHovering = isHovering;
  }
}
