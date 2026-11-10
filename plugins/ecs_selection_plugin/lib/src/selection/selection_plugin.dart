import 'package:ecsly/ecsly.dart';

import 'resources/selection_state_resource.dart';

/// ECS Plugin for selection state management.
///
/// Registers [SelectionStateResource]. The [selectionSystem] is registered
/// separately in the host schedule so ordering can be controlled.
class SelectionPlugin extends Plugin {
  /// Creates the selection plugin instance.
  const SelectionPlugin();

  @override
  String get name => 'Selection';

  @override
  void install(final World world) {
    world.upsertResource(SelectionStateResource());
  }
}
