import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ecs_spatial_core/ecs_spatial_core.dart';
import 'package:ecsly/ecsly.dart';

/// Shared utilities for camera position calculations and target evaluation.
///
/// Provides common functions used across camera systems for extracting positions
/// and calculating aggregate positions from entity groups.
///
/// Renderer/game agnostic: entity positions are read through
/// [PositionConfigResource] (ecs_spatial_core), NOT a specific game's position
/// component. A host that wants camera-follow / zoom-to-fit registers a
/// [PositionConfigResource] pointing at its own position column; entities
/// without one are skipped gracefully. (The original private package read a
/// game2d `PositionComponent` first; that coupling was severed when this
/// package was extracted to the public repo, since hosts bring their own
/// position model.)
class CameraPositionUtils {
  /// Private constructor to prevent instantiation.
  CameraPositionUtils._();

  /// Calculates the average position from a list of entities.
  ///
  /// Returns null if no valid positions found.
  static ui.Offset? calculateAveragePosition(
    final World world,
    final List<Entity> entities,
  ) {
    double sumX = 0;
    double sumY = 0;
    int count = 0;

    for (final entity in entities) {
      final (ext, valid) = world.getEntity(entity);
      if (!valid) continue;
      final targetPos = getPositionComponent(ext.toExtension());
      if (targetPos == null) continue;
      sumX += targetPos.dx;
      sumY += targetPos.dy;
      count++;
    }

    if (count == 0) return null;
    return ui.Offset(sumX / count, sumY / count);
  }

  /// Calculates the center of bounds for a list of entities.
  ///
  /// Returns null if no valid positions found.
  static ui.Offset? calculateBoundsCenter(
    final World world,
    final List<Entity> entities,
  ) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final entity in entities) {
      final (ext, valid) = world.getEntity(entity);
      if (!valid) continue;
      final targetPos = getPositionComponent(ext.toExtension());
      if (targetPos == null) continue;
      minX = math.min(minX, targetPos.dx);
      maxX = math.max(maxX, targetPos.dx);
      minY = math.min(minY, targetPos.dy);
      maxY = math.max(maxY, targetPos.dy);
    }

    if (minX == double.infinity) return null;
    return ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  /// Extracts position as Offset from an entity via [PositionConfigResource]
  /// (data-only, renderer/game agnostic). Returns null if no position config
  /// is registered or the entity has no position column.
  static ui.Offset? getPositionComponent(final WorldEntityExtension ext) {
    final world = ext.base.world;
    final entity = ext.base.entity;

    if (world.resources.has<PositionConfigResource>()) {
      final config = world.getResource<PositionConfigResource>();
      final extracted = positionFromConfig(world, entity, config);
      if (extracted != null) {
        return ui.Offset(extracted.$1, extracted.$2);
      }
    }

    return null;
  }
}
