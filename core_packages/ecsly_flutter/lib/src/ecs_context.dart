import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_scope.dart';

/// Discoverable Flutter context handle for ecsly state.
class EcsContext {
  const EcsContext(this._context);

  final BuildContext _context;

  World get world => EcsScope.worldOf(_context, listen: false);

  EcsController get controller => EcsScope.requireControllerOf(_context);

  EcsController? get maybeController => EcsScope.controllerOf(_context);

  T readResource<T extends Resource>() => world.getResource<T>();

  T getResource<T extends Resource>() => readResource<T>();

  T? maybeReadResource<T extends Resource>() => world.maybeGetResource<T>();

  T? maybeGetResource<T extends Resource>() => maybeReadResource<T>();

  R selectResource<T extends Resource, R>(final R Function(T resource) select) {
    EcsScope.dependOnResource<T>(_context);
    final listenedWorld = EcsScope.worldOf(_context);
    final resource = listenedWorld.maybeGetResource<T>();
    if (resource == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('No ECS resource of type $T found.'),
        ErrorDescription(
          'Use maybeSelectEcsResource for optional state, or upsert $T before '
          'this widget builds.',
        ),
      ]);
    }
    return select(resource);
  }

  R? maybeSelectResource<T extends Resource, R>(
    final R Function(T resource) select,
  ) {
    EcsScope.dependOnResource<T>(_context);
    final listenedWorld = EcsScope.worldOf(_context);
    final resource = listenedWorld.maybeGetResource<T>();
    if (resource == null) return null;
    return select(resource);
  }

  Entity findEntityWithComponent<C extends Component>({
    required final EcsComponentWhere<C> where,
  }) => world.findEcsEntityWithComponent<C>(where: where);

  Entity? maybeFindEntityWithComponent<C extends Component>({
    required final EcsComponentWhere<C> where,
  }) => world.maybeFindEcsEntityWithComponent<C>(where: where);

  C getComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => world.getEcsComponent<C>(entity: entity, where: where);

  C? maybeGetComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => world.maybeGetEcsComponent<C>(entity: entity, where: where);

  C readComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => getComponent<C>(entity: entity, where: where);

  C? maybeReadComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => maybeGetComponent<C>(entity: entity, where: where);

  R selectComponent<C extends Component, R>(
    final R Function(C component) select, {
    final Entity? entity,
    final EcsComponentWhere<C>? where,
    final R Function(Entity entity, C component)? selectWithEntity,
  }) {
    EcsScope.dependOnComponent<C>(_context, entity: entity);
    final listenedWorld = EcsScope.worldOf(_context);
    final resolvedEntity =
        entity ??
        (where == null
            ? null
            : listenedWorld.maybeFindEcsEntityWithComponent<C>(where: where));
    if (resolvedEntity == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('No ECS component of type $C matched this lookup.'),
        ErrorDescription(
          entity == null
              ? 'Pass entity: when you already have an Entity, or pass where: '
                    'to find a component from app/domain data.'
              : 'The entity may have been despawned, or it does not have $C.',
        ),
      ]);
    }
    final component = listenedWorld.maybeGetEcsComponent<C>(
      entity: resolvedEntity,
      where: where,
    );
    if (component == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('No ECS component of type $C matched this lookup.'),
        ErrorDescription(
          'The entity may have been despawned, or it does not have $C.',
        ),
      ]);
    }
    return selectWithEntity?.call(resolvedEntity, component) ??
        select(component);
  }

  R? maybeSelectComponent<C extends Component, R>(
    final R Function(C component) select, {
    final Entity? entity,
    final EcsComponentWhere<C>? where,
    final R Function(Entity entity, C component)? selectWithEntity,
  }) {
    EcsScope.dependOnComponent<C>(_context, entity: entity);
    final listenedWorld = EcsScope.worldOf(_context);
    final resolvedEntity =
        entity ??
        (where == null
            ? null
            : listenedWorld.maybeFindEcsEntityWithComponent<C>(where: where));
    if (resolvedEntity == null) return null;
    final component = listenedWorld.maybeGetEcsComponent<C>(
      entity: resolvedEntity,
      where: where,
    );
    if (component == null) return null;
    return selectWithEntity?.call(resolvedEntity, component) ??
        select(component);
  }

  Future<T> runAction<T>(final EcsAction<T> action) =>
      controller.runAction(action);

  EcsActionStatus actionStatusOf(final Object key) =>
      controller.actionStatusOf(key);
}

/// Convenient ecsly accessors on Flutter [BuildContext].
extension EcsBuildContextX on BuildContext {
  EcsContext get ecs => EcsContext(this);

  World get ecsWorld => ecs.world;

  EcsController get ecsController => ecs.controller;

  EcsController? get maybeEcsController => ecs.maybeController;

  T readEcsResource<T extends Resource>() => ecs.readResource<T>();

  T getEcsResource<T extends Resource>() => ecs.getResource<T>();

  T? maybeReadEcsResource<T extends Resource>() => ecs.maybeReadResource<T>();

  T? maybeGetEcsResource<T extends Resource>() => ecs.maybeGetResource<T>();

  R selectEcsResource<T extends Resource, R>(
    final R Function(T resource) select,
  ) => ecs.selectResource<T, R>(select);

  R? maybeSelectEcsResource<T extends Resource, R>(
    final R Function(T resource) select,
  ) => ecs.maybeSelectResource<T, R>(select);

  Entity findEcsEntityWithComponent<C extends Component>({
    required final EcsComponentWhere<C> where,
  }) => ecs.findEntityWithComponent<C>(where: where);

  Entity? maybeFindEcsEntityWithComponent<C extends Component>({
    required final EcsComponentWhere<C> where,
  }) => ecs.maybeFindEntityWithComponent<C>(where: where);

  C getEcsComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => ecs.getComponent<C>(entity: entity, where: where);

  C? maybeGetEcsComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => ecs.maybeGetComponent<C>(entity: entity, where: where);

  C readEcsComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => ecs.readComponent<C>(entity: entity, where: where);

  C? maybeReadEcsComponent<C extends Component>({
    required final Entity entity,
    final EcsComponentWhere<C>? where,
  }) => ecs.maybeReadComponent<C>(entity: entity, where: where);

  R selectEcsComponent<C extends Component, R>(
    final R Function(C component) select, {
    final Entity? entity,
    final EcsComponentWhere<C>? where,
    final R Function(Entity entity, C component)? selectWithEntity,
  }) => ecs.selectComponent<C, R>(
    select,
    entity: entity,
    where: where,
    selectWithEntity: selectWithEntity,
  );

  R? maybeSelectEcsComponent<C extends Component, R>(
    final R Function(C component) select, {
    final Entity? entity,
    final EcsComponentWhere<C>? where,
    final R Function(Entity entity, C component)? selectWithEntity,
  }) => ecs.maybeSelectComponent<C, R>(
    select,
    entity: entity,
    where: where,
    selectWithEntity: selectWithEntity,
  );

  Future<T> runEcsAction<T>(final EcsAction<T> action) => ecs.runAction(action);

  EcsActionStatus ecsActionStatusOf(final Object key) =>
      ecs.actionStatusOf(key);
}
