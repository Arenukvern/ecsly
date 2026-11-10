import 'package:ecsly/ecsly.dart';

/// Tracks the currently selected object.
class SelectionStateResource extends Resource {
  /// Key of the selected object (from [PickingResultResource.hitKey]).
  String? selectedKey;

  /// Hit position in world space at time of selection.
  /// X position in world space.
  double hitX = 0;

  /// Y position in world space.
  double hitY = 0;

  /// Z position in world space.
  double hitZ = 0;

  /// Hit normal in world space at time of selection.
  /// X normal component.
  double normalX = 0;

  /// Y normal component.
  double normalY = 0;

  /// Z normal component.
  double normalZ = 0;
}
