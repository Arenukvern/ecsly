import 'package:ecsly/ecsly.dart';

/// Data-only resource: which component stores 2D position (x, y).
///
/// Set by plugins (e.g. Game2DPlugin) so input/camera systems can read and
/// write position without depending on a specific component type.
/// Logic for reading/writing lives in systems or [positionFromConfig] /
/// [applyPositionDelta].
class PositionConfigResource extends Resource {
  /// Component ID for the position component (e.g. PositionComponent).
  final ComponentId positionComponentId;

  /// Floats per entity in the column (e.g. 2 for x,y or 4 for x,y,z,w).
  final int stride;

  PositionConfigResource({required this.positionComponentId, this.stride = 2});
}
