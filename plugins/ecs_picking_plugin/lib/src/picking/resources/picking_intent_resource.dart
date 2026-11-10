import 'package:ecsly/ecsly.dart';

/// Intent resource for requesting a picking raycast.
///
/// Set [pending] to true and fill in the ray origin / direction
/// to trigger a pick on the next tick. Backends drain [pending]
/// and write results to [PickingResultResource].
class PickingIntentResource extends Resource {
  bool pending = false;
  double rayOriginX = 0;
  double rayOriginY = 0;
  double rayOriginZ = 0;
  double rayDirX = 0;
  double rayDirY = 0;
  double rayDirZ = 0;

  /// Maximum pick distance.
  double maxDist = 100;
}
