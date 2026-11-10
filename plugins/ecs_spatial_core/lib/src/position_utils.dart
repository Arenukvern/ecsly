import 'package:ecsly/ecsly.dart';

import 'position_config_resource.dart';

/// Applies (dx, dy) to the entity's position using [config]. Returns true if applied.
///
/// Pure helper; no callbacks. Use from systems (e.g. drag).
bool applyPositionDelta(
  final World world,
  final Entity entity,
  final double dx,
  final double dy,
  final PositionConfigResource config,
) {
  final (worldEntity, valid) = world.getEntity(entity);
  if (!valid) return false;

  final rowIndex = worldEntity.archetype.getRowIndex(
    worldEntity.entity,
    world.entities,
  );
  if (rowIndex == null) return false;

  final column = worldEntity.archetype.getColumn(config.positionComponentId);
  if (column is! FloatColumn) return false;

  final x = column.getValue(rowIndex, 0);
  final y = column.getValue(rowIndex, 1);
  column.setValue(rowIndex, 0, x + dx);
  column.setValue(rowIndex, 1, y + dy);
  return true;
}

/// Returns (x, y) world position for [entity] using [config], or null if missing.
///
/// Pure helper; no callbacks. Use from systems or input/camera code.
(double x, double y)? positionFromConfig(
  final World world,
  final Entity entity,
  final PositionConfigResource config,
) {
  final (worldEntity, valid) = world.getEntity(entity);
  if (!valid) return null;

  final rowIndex = worldEntity.archetype.getRowIndex(
    worldEntity.entity,
    world.entities,
  );
  if (rowIndex == null) return null;

  final column = worldEntity.archetype.getColumn(config.positionComponentId);
  if (column is! FloatColumn) return null;

  return (column.getValue(rowIndex, 0), column.getValue(rowIndex, 1));
}
