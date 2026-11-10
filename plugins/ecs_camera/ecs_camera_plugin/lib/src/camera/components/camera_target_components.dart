import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

/// Base sealed class for camera targets (mutually exclusive).
///
/// An entity can only have one target component at a time.
/// This ensures clear camera behavior without conflicts.
sealed class CameraTarget extends Component {}

/// Follow single entity with optional offset and dead zone.
///
/// Camera will smoothly follow the target entity's position.
/// Supports offset for leading shots and dead zone for natural following.
class FollowTarget extends CameraTarget {
  /// Creates a single-entity follow target with optional framing settings.
  FollowTarget(
    this.entity, {
    this.offset = ui.Offset.zero,
    this.deadZone = 0.0,
  });

  /// Entity to follow
  final Entity entity;

  /// Camera offset from target position
  final ui.Offset offset;

  /// Dead zone radius - camera won't update if target is within this radius
  /// of current camera position. Set to 0 to disable.
  final double deadZone;
}

/// Mode for following multiple entities.
enum FollowGroupMode {
  /// Center on average position of all entities
  average,

  /// Show all entities with padding (adjusts zoom if needed)
  fitBounds,
}

/// Follow multiple entities (average or bounds-fitting).
///
/// Useful for split-screen or showing multiple players.
class FollowGroupTarget extends CameraTarget {
  /// Creates a multi-entity follow target.
  FollowGroupTarget(
    this.entities, {
    this.mode = FollowGroupMode.average,
    this.padding = 100.0,
  });

  /// List of entities to follow
  final List<Entity> entities;

  /// How to calculate camera position from multiple targets
  final FollowGroupMode mode;

  /// Padding around bounds (for fitBounds mode)
  final double padding;
}

/// Fixed world position.
///
/// Camera stays at a fixed world position regardless of entity movement.
/// Useful for strategy games, cutscenes, or static views.
class FixedTarget extends CameraTarget {
  /// Creates a fixed world-space camera target.
  FixedTarget(this.x, this.y);

  /// Fixed X position in world coordinates
  final double x;

  /// Fixed Y position in world coordinates
  final double y;
}

/// Free-moving camera (no automatic target).
///
/// Camera can be moved via input systems (WASD, drag, etc.).
/// Position is controlled manually by input systems.
class FreeTarget extends CameraTarget {
  /// Creates a free target with no automatic tracking.
  FreeTarget();
}
