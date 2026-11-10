/// Hit testing utilities for the input system.
library;

import 'package:ecsly/ecsly.dart';

import '../draggable_components/hit_shape.dart';
import '../draggable_components/interactive_element.dart';
import 'entity_world_position.dart';

/// Performs hit testing to determine if a pointer position intersects an interactive element.
///
/// Uses the entity's position component and the interactive element's hit shape
/// to perform hit testing in world coordinates. All coordinates are pure doubles.
bool hitTest(
  final double pointerWorldX,
  final double pointerWorldY,
  final Entity entity,
  final World world,
) {
  final position = extractEntityWorldPosition(entity, world);
  if (position == null) return false;

  final interactive = world.getEntity(entity).$1.get<InteractiveElement>();
  if (interactive == null) return false;

  final shape = interactive.hitShape;
  final (cx, cy) = position;
  switch (shape.type) {
    case HitShapeType.circle:
      final radius = shape.radius ?? 0.0;
      final dx = pointerWorldX - cx;
      final dy = pointerWorldY - cy;
      return dx * dx + dy * dy <= radius * radius;
    case HitShapeType.rectangle:
      final width = shape.width ?? 0.0;
      final height = shape.height ?? 0.0;
      final halfW = width / 2;
      final halfH = height / 2;
      return pointerWorldX >= cx - halfW &&
          pointerWorldX <= cx + halfW &&
          pointerWorldY >= cy - halfH &&
          pointerWorldY <= cy + halfH;
  }
}
