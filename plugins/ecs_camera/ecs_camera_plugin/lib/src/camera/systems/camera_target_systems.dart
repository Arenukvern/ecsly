import 'package:ecsly/ecsly.dart';

import '../camera_position_utils.dart';
import '../components/camera_components.dart';

// Note: PositionComponent from game2d plugin is optional.
// Systems gracefully skip entities without PositionComponent.

/// Updates camera target for FixedTarget.
void cameraFixedTargetSystem(final World world) {
  for (final (_, pos, fixedTarget)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            FixedTarget,
            FixedTarget
          >()) {
    pos.setTarget(fixedTarget.x, fixedTarget.y);
  }
}

/// Updates camera target for FollowGroupTarget.
void cameraFollowGroupTargetSystem(final World world) {
  for (final (_, pos, groupTarget)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            FollowGroupTarget,
            FollowGroupTarget
          >()) {
    if (groupTarget.entities.isEmpty) continue;

    switch (groupTarget.mode) {
      case FollowGroupMode.average:
        _updateAveragePosition(world, pos, groupTarget.entities);
      case FollowGroupMode.fitBounds:
        _updateBoundsPosition(
          world,
          pos,
          groupTarget.entities,
          groupTarget.padding,
        );
    }
  }
}

/// Updates camera target position based on FollowTarget component.
void cameraFollowTargetSystem(final World world) {
  for (final (_, pos, followTarget)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            FollowTarget,
            FollowTarget
          >()) {
    final (targetExt, valid) = world.getEntity(followTarget.entity);
    if (!valid) continue;

    // PositionComponent is optional (from game2d plugin)
    // Use dynamic access to avoid compile-time dependency
    final targetPos = CameraPositionUtils.getPositionComponent(
      targetExt.toExtension(),
    );
    if (targetPos == null) continue;

    final newX = targetPos.dx + followTarget.offset.dx;
    final newY = targetPos.dy + followTarget.offset.dy;

    // Dead zone check
    if (followTarget.deadZone > 0) {
      final dx = newX - pos.targetX;
      final dy = newY - pos.targetY;
      if (dx * dx + dy * dy < followTarget.deadZone * followTarget.deadZone) {
        continue;
      }
    }

    pos.setTarget(newX, newY);
  }
}

// FreeTarget has no system - position controlled manually by input systems

void _updateAveragePosition(
  final World world,
  final CameraPosition pos,
  final List<Entity> entities,
) {
  final averagePos = CameraPositionUtils.calculateAveragePosition(
    world,
    entities,
  );
  if (averagePos != null) {
    pos.setTarget(averagePos.dx, averagePos.dy);
  }
}

void _updateBoundsPosition(
  final World world,
  final CameraPosition pos,
  final List<Entity> entities,
  final double padding,
) {
  final boundsCenter = CameraPositionUtils.calculateBoundsCenter(
    world,
    entities,
  );
  if (boundsCenter != null) {
    pos.setTarget(boundsCenter.dx, boundsCenter.dy);
  }
}
