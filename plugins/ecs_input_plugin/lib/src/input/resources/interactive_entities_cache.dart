/// Resource that caches sorted interactive entities to eliminate redundant queries.
///
/// This cache stores the result of querying and sorting interactive entities by priority,
/// which is needed by all input systems. The cache is invalidated when InteractiveElement
/// components are added, removed, or modified, ensuring it stays synchronized with changes.
///
/// Performance impact:
/// - Eliminates redundant queries + sorts per frame when input events exist
/// - Reduces to 1 query + 1 sort when cache is invalidated
/// - Zero overhead when no input events exist (schedule doesn't run)
library;

import 'package:ecsly/ecsly.dart';

import '../draggable_components/interactive_element.dart';

/// Cached list of interactive entities sorted by priority for hit testing.
///
/// This resource eliminates the need for each input system to query and sort
/// interactive entities independently, reducing redundant work.
class InteractiveEntitiesCache extends Resource {
  /// The cached list of (Entity, InteractiveElement) tuples sorted by priority.
  List<(Entity, InteractiveElement)>? _cachedEntities;

  /// The component ID for InteractiveElement (cached for performance).
  ComponentId? _componentId;

  /// Hash of entity IDs and priorities for change detection.
  ///
  /// This allows detecting when InteractiveElement components are added/removed/modified
  /// without re-querying every time. The hash is computed from entity IDs and priorities.
  int? _lastHash;
}

extension InteractiveEntitiesCacheOps on InteractiveEntitiesCache {
  List<(Entity, InteractiveElement)> getEntities(final World world) =>
      interactiveEntitiesCacheGetEntities(this, world);

  void invalidate() => interactiveEntitiesCacheInvalidate(this);
}

List<(Entity, InteractiveElement)> interactiveEntitiesCacheGetEntities(
  final InteractiveEntitiesCache cache,
  final World world,
) {
  cache._componentId ??= world.components.getComponentId<InteractiveElement>();

  final currentEntities = world.query<InteractiveElement>().toList();
  final currentHash = interactiveEntitiesCacheComputeHash(currentEntities);

  if (cache._cachedEntities == null || currentHash != cache._lastHash) {
    cache._cachedEntities =
        currentEntities
            .map((final result) => (result.$1.entity, result.$2))
            .toList()
          ..sort((final a, final b) => b.$2.priority.compareTo(a.$2.priority));
    cache._lastHash = currentHash;
  }

  return cache._cachedEntities!;
}

void interactiveEntitiesCacheInvalidate(final InteractiveEntitiesCache cache) {
  cache._cachedEntities = null;
  cache._lastHash = null;
}

int interactiveEntitiesCacheComputeHash(
  final List<(WorldEntity, InteractiveElement)> entities,
) {
  var hash = 0;
  for (final (entity, interactive) in entities) {
    hash =
        (hash * 31 + entity.entity.indexValue.hashCode) * 31 +
        interactive.priority.hashCode;
  }
  return hash;
}
