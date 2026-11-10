import 'package:ecsly/ecsly.dart';

import '../resources/selection_manager.dart';

/// System that automatically removes dead entities from SelectionManager.
///
/// Runs each frame to prevent memory leaks from despawned entities
/// remaining in selection state.
void selectionCleanupSystem(final World world) {
  final selectionManager = world.resources.has<SelectionManager>()
      ? world.getResource<SelectionManager>()
      : null;

  if (selectionManager == null) return;

  selectionManager.removeInvalidEntities(world);
}
