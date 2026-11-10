import 'package:ecsly/ecsly.dart';

import '../draggable_components/hit_shape.dart';
import '../draggable_components/interactive_element.dart';
import 'entity_world_position.dart';

/// Unified hit testing utility (pure doubles, no dart:ui).
class HitTestingUtils {
  /// Find entity at the given world position (worldX, worldY).
  static Entity? findEntityAt(
    final World world,
    final double worldX,
    final double worldY, {
    final double? zoomLevel,
    final bool Function(Entity entity, WorldEntity ext)? filter,
  }) {
    for (final (entity, interactive) in world.query<InteractiveElement>()) {
      if (filter != null) {
        final (ext, valid) = world.getEntity(entity.entity);
        if (!valid) continue;
        if (!filter(entity.entity, ext)) continue;
      }
      if (testHit(entity.entity, interactive, worldX, worldY, world)) {
        return entity.entity;
      }
    }
    return null;
  }

  /// Test if (worldX, worldY) hits an interactive element.
  static bool testHit(
    final Entity entity,
    final InteractiveElement interactive,
    final double worldX,
    final double worldY,
    final World world,
  ) {
    final position = extractEntityWorldPosition(entity, world);
    if (position == null) return false;
    final (cx, cy) = position;
    final hitShape = interactive.hitShape;
    return switch (hitShape.type) {
      HitShapeType.circle => _testCircle(
        cx,
        cy,
        worldX,
        worldY,
        hitShape.radius ?? interactive.hitShape.radius ?? 0.0,
      ),
      HitShapeType.rectangle => _testRectangle(
        cx,
        cy,
        worldX,
        worldY,
        hitShape.width ?? 0.0,
        hitShape.height ?? 0.0,
      ),
    };
  }

  static bool _testCircle(
    final double centerX,
    final double centerY,
    final double pointX,
    final double pointY,
    final double radius,
  ) {
    final dx = pointX - centerX;
    final dy = pointY - centerY;
    return dx * dx + dy * dy <= radius * radius;
  }

  static bool _testRectangle(
    final double centerX,
    final double centerY,
    final double pointX,
    final double pointY,
    final double width,
    final double height,
  ) {
    final halfW = width / 2;
    final halfH = height / 2;
    return pointX >= centerX - halfW &&
        pointX <= centerX + halfW &&
        pointY >= centerY - halfH &&
        pointY <= centerY + halfH;
  }
}
