import 'package:ecsly_app/ecsly_app.dart';

/// Optional dependency hint for selectors derived from multiple ECS slices.
///
/// Omit this for correctness-first broad refreshes. Provide it when a selector
/// only depends on known component/resource types and can safely skip unrelated
/// tracked world changes.
final class EcsWorldSelectorDependencies {
  const EcsWorldSelectorDependencies({
    this.resourceTypes = const <Type>[],
    this.componentTypes = const <Type>[],
    this.structural = false,
  });

  final Iterable<Type> resourceTypes;
  final Iterable<Type> componentTypes;
  final bool structural;

  bool get isEmpty =>
      !structural && resourceTypes.isEmpty && componentTypes.isEmpty;
}

/// Read-only view of the controller's most recent notification boundary.
final class EcsControllerChangeView {
  const EcsControllerChangeView({
    required this.world,
    required this.invalidation,
  });

  final World world;

  final EcsInvalidationBatch invalidation;
}
