library;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_spatial_core/ecs_spatial_core.dart';

/// Resolves entity world position via [PositionConfigResource] (data-only).
/// Returns (x, y) in world coordinates or null if not available.
(double x, double y)? extractEntityWorldPosition(
  final Entity entity,
  final World world,
) {
  if (!world.resources.has<PositionConfigResource>()) {
    return null;
  }
  final config = world.getResource<PositionConfigResource>();
  return positionFromConfig(world, entity, config);
}
