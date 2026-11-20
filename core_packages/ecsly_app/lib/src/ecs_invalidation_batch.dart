// ignore_for_file: prefer_constructors_over_static_methods

import 'package:ecsly/ecsly.dart';

/// Coarse app/host invalidation hint for UI and integration layers.
///
/// This is intentionally outside ECS core. Core owns simulation state and query
/// topology revisions; hosts opt in to higher-level invalidation when they want
/// selective rebuilds.
final class EcsInvalidationBatch {
  const EcsInvalidationBatch({
    this.broad = false,
    this.structural = false,
    this.resourceTypes = const <Type>[],
    this.componentTypes = const <Type>[],
    this.touchedEntities = const <Entity>[],
    this.entityDetailOverflow = false,
  });

  const EcsInvalidationBatch.empty()
    : broad = false,
      structural = false,
      resourceTypes = const <Type>[],
      componentTypes = const <Type>[],
      touchedEntities = const <Entity>[],
      entityDetailOverflow = false;

  const EcsInvalidationBatch.broad()
    : broad = true,
      structural = true,
      resourceTypes = const <Type>[],
      componentTypes = const <Type>[],
      touchedEntities = const <Entity>[],
      entityDetailOverflow = true;

  static EcsInvalidationBatch resource<T extends Resource>() =>
      EcsInvalidationBatch(resourceTypes: <Type>[T]);

  static EcsInvalidationBatch resources(Iterable<Type> types) =>
      EcsInvalidationBatch(resourceTypes: List<Type>.of(types));

  static EcsInvalidationBatch component<T extends Component>({
    Entity? entity,
    bool structural = false,
  }) => EcsInvalidationBatch(
    structural: structural,
    componentTypes: <Type>[T],
    touchedEntities: entity == null ? const <Entity>[] : <Entity>[entity],
  );

  static EcsInvalidationBatch components(
    Iterable<Type> types, {
    Iterable<Entity> entities = const <Entity>[],
    bool structural = false,
    bool entityDetailOverflow = false,
  }) => EcsInvalidationBatch(
    structural: structural,
    componentTypes: List<Type>.of(types),
    touchedEntities: List<Entity>.of(entities),
    entityDetailOverflow: entityDetailOverflow,
  );

  static EcsInvalidationBatch structuralChange() =>
      const EcsInvalidationBatch(structural: true);

  final bool broad;
  final bool structural;
  final List<Type> resourceTypes;
  final List<Type> componentTypes;
  final List<Entity> touchedEntities;
  final bool entityDetailOverflow;

  bool get isEmpty =>
      !broad &&
      !structural &&
      resourceTypes.isEmpty &&
      componentTypes.isEmpty &&
      touchedEntities.isEmpty &&
      !entityDetailOverflow;

  bool matchesResourceType(Type type) =>
      broad || resourceTypes.contains(type);

  bool matchesComponentType(Type type, {Entity? entity}) {
    if (broad) return true;
    if (structural) return true;
    if (!componentTypes.contains(type)) return false;
    if (entity == null) return true;
    if (entityDetailOverflow || touchedEntities.isEmpty) return true;
    return touchedEntities.contains(entity);
  }

  bool matchesStructural() => broad || structural;

  EcsInvalidationBatch merge(EcsInvalidationBatch other) {
    if (broad || other.broad) return const EcsInvalidationBatch.broad();
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    return EcsInvalidationBatch(
      structural: structural || other.structural,
      resourceTypes: _mergeUnique(resourceTypes, other.resourceTypes),
      componentTypes: _mergeUnique(componentTypes, other.componentTypes),
      touchedEntities: _mergeUnique(touchedEntities, other.touchedEntities),
      entityDetailOverflow: entityDetailOverflow || other.entityDetailOverflow,
    );
  }

  static List<T> _mergeUnique<T>(List<T> left, List<T> right) {
    if (left.isEmpty) return List<T>.of(right);
    if (right.isEmpty) return List<T>.of(left);
    final result = <T>[...left];
    for (final value in right) {
      if (!result.contains(value)) result.add(value);
    }
    return result;
  }
}
