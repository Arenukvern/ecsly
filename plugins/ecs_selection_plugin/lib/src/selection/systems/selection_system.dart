import 'package:ecs_picking_plugin/ecs_picking_plugin.dart';
import 'package:ecsly/ecsly.dart';

import '../resources/selection_state_resource.dart';

/// Reads [PickingResultResource] and updates [SelectionStateResource].
///
/// When a new picking hit is available, updates the selected key and
/// stores the hit position / normal. Clears [hasNewHit] after processing.
/// Schedule in Sim after the picking backend.
void selectionSystem(final World world) {
  final picking = world.getResource<PickingResultResource>();
  if (!picking.hasNewHit) {
    return;
  }
  picking.hasNewHit = false;

  final state = world.getResource<SelectionStateResource>();
  state
    ..selectedKey = picking.hitKey
    ..hitX = picking.hitX
    ..hitY = picking.hitY
    ..hitZ = picking.hitZ
    ..normalX = picking.normalX
    ..normalY = picking.normalY
    ..normalZ = picking.normalZ;
}
