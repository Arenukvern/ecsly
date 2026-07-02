import 'package:ecsly/ecsly.dart';

typedef EcsComponentWhere<T extends Component> =
    bool Function(Entity entity, T component);

/// Flutter/app lookup helpers on an ecsly [World].
///
/// The methods here are cold UI/domain conveniences. Domain ids are normal
/// components, and repeated id lookup belongs in small app/plugin projections.
/// Hot systems should use core query/raw chunk APIs.
extension EcsComponentLookupX on World {
  /// Direct entity lookup wrapper for core [World.maybeGetComponent].
  T? maybeGetEcsComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) {
    final component = maybeGetComponent<T>(entity);
    if (component == null) return null;
    if (where != null && !where(entity, component)) return null;
    return component;
  }

  /// Direct entity lookup wrapper that throws when [entity] has no [T].
  T getEcsComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) {
    final component = maybeGetEcsComponent<T>(entity: entity, where: where);
    if (component != null) return component;
    throw StateError('No component of type $T found on entity $entity.');
  }

  /// Cold app/domain lookup for Flutter/app code.
  Entity? maybeFindEcsEntityWithComponent<T extends Component>({
    required final EcsComponentWhere<T> where,
  }) {
    final componentId = components.getComponentId<T>();
    final componentQuery = ComponentQuery(world: this, required: [componentId]);
    for (final archetype in componentQuery.matchingArchetypes) {
      final rows = archetype.entities;
      for (var row = 0; row < rows.length; row += 1) {
        final entity = rows[row];
        if (!_isCurrentEntityRow(this, entity, archetype.archetypeId, row)) {
          continue;
        }
        final component = archetype.getComponentByIndex<T>(row, components);
        if (component != null && where(entity, component)) {
          return entity;
        }
      }
    }

    return null;
  }

  /// Cold app/domain lookup that throws when no entity matches.
  Entity findEcsEntityWithComponent<T extends Component>({
    required final EcsComponentWhere<T> where,
  }) {
    final entity = maybeFindEcsEntityWithComponent<T>(where: where);
    if (entity != null) return entity;
    throw StateError(
      'No entity with component type $T matched the lookup predicate.',
    );
  }
}

bool _isCurrentEntityRow(
  final World world,
  final Entity entity,
  final ArchetypeId archetypeId,
  final int row,
) {
  if (!world.entities.isAlive(entity)) return false;
  final location = world.entities.getLocation(entity);
  return location.archetypeId == archetypeId && location.archetypeRow == row;
}
