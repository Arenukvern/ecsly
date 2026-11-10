import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

import '../camera_position_utils.dart';
import '../components/camera_components.dart';

/// Handles camera target blending/transitions.
///
/// Interpolates between two camera targets over time.
/// Automatically removes the blend component when transition completes.
void cameraBlendSystem(final World world) {
  final dt = world.getResource<DeltaTimeResource>().deltaTime;

  for (final (entity, pos, blend)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            CameraBlend,
            CameraBlend
          >()) {
    if (blend.duration.inSeconds <= 0) {
      // Complete immediately if duration is zero or negative
      blend.progress = 1.0;
    } else {
      blend.progress += dt / blend.duration.inSeconds;
    }

    if (blend.progress >= 1.0) {
      // Transition complete - swap to new target
      final (worldEntity, valid) = world.getEntity(entity.entity);
      if (valid) {
        worldEntity.remove<CameraBlend>();
        // Remove old target and add new target
        _removeTargetComponent(worldEntity);
        _addTargetComponent(worldEntity, blend.toTarget);
      }
    } else {
      // Interpolate between from and to targets
      final t = blend.curve.transform(blend.progress);
      final fromPos = _evaluateTarget(world, blend.fromTarget);
      final toPos = _evaluateTarget(world, blend.toTarget);

      if (fromPos != null && toPos != null) {
        pos.setTarget(
          fromPos.dx + (toPos.dx - fromPos.dx) * t,
          fromPos.dy + (toPos.dy - fromPos.dy) * t,
        );
      }
    }
  }
}

void _addTargetComponent(final WorldEntity entity, final CameraTarget target) {
  switch (target) {
    case FollowTarget():
      entity.insert(target);
    case FollowGroupTarget():
      entity.insert(target);
    case FixedTarget():
      entity.insert(target);
    case FreeTarget():
      entity.insert(target);
  }
}

ui.Offset? _evaluateTarget(final World world, final CameraTarget target) =>
    switch (target) {
      FollowTarget(:final entity, :final offset) => () {
        final (ext, valid) = world.getEntity(entity);
        if (!valid) return null;
        final targetPos = CameraPositionUtils.getPositionComponent(
          ext.toExtension(),
        );
        if (targetPos == null) return null;
        return ui.Offset(targetPos.dx + offset.dx, targetPos.dy + offset.dy);
      }(),
      FollowGroupTarget(:final entities, :final mode) => () {
        if (entities.isEmpty) return null;
        switch (mode) {
          case FollowGroupMode.average:
            return CameraPositionUtils.calculateAveragePosition(
              world,
              entities,
            );
          case FollowGroupMode.fitBounds:
            return CameraPositionUtils.calculateBoundsCenter(world, entities);
        }
      }(),
      FixedTarget(:final x, :final y) => ui.Offset(x, y),
      FreeTarget() => null, // Free target has no position
    };

void _removeTargetComponent(final WorldEntity entity) {
  entity.remove<FollowTarget>();
  entity.remove<FollowGroupTarget>();
  entity.remove<FixedTarget>();
  entity.remove<FreeTarget>();
}
