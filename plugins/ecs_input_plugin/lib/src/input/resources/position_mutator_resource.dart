// Re-export data-only position config and apply helper from spatial_core.
// Prefer importing from ecs_spatial_core when only position config is needed.
export 'package:ecs_spatial_core/ecs_spatial_core.dart'
    show PositionConfigResource, applyPositionDelta, positionFromConfig;
