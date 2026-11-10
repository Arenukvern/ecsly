import 'package:ecsly/ecsly.dart';

import 'resources/picking_intent_resource.dart';
import 'resources/picking_result_resource.dart';

/// Generic picking plugin — registers intent and result resources.
///
/// Backends (physics raycast, mesh intersection, GPU picking, etc.)
/// register their own systems that drain [PickingIntentResource]
/// and write to [PickingResultResource].
class PickingPlugin extends Plugin {
  const PickingPlugin();

  @override
  String get name => 'Picking';

  @override
  void install(final World world) {
    world.upsertResource(PickingIntentResource());
    world.upsertResource(PickingResultResource());
  }
}
