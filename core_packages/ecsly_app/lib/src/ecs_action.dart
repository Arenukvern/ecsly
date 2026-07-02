import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

import 'ecs_component_lookup.dart';
import 'ecs_invalidation_batch.dart';

/// Current execution phase for an [EcsAction].
enum EcsActionPhase { idle, running, succeeded, failed, cancelled }

/// Immutable status snapshot for one action key.
@immutable
class EcsActionStatus {
  const EcsActionStatus({
    required this.phase,
    required this.runId,
    required this.startedAt,
    this.finishedAt,
    this.progress,
    this.result,
    this.error,
    this.stackTrace,
  });

  const EcsActionStatus.idle()
    : phase = EcsActionPhase.idle,
      runId = 0,
      startedAt = null,
      finishedAt = null,
      progress = null,
      result = null,
      error = null,
      stackTrace = null;

  final EcsActionPhase phase;
  final int runId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final double? progress;
  final Object? result;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isIdle => phase == EcsActionPhase.idle;
  bool get isRunning => phase == EcsActionPhase.running;
  bool get hasFailed => phase == EcsActionPhase.failed;
  bool get hasSucceeded => phase == EcsActionPhase.succeeded;
  bool get isCancelled => phase == EcsActionPhase.cancelled;

  EcsActionStatus copyWith({
    final EcsActionPhase? phase,
    final int? runId,
    final DateTime? startedAt,
    final DateTime? finishedAt,
    final double? progress,
    final Object? result,
    final Object? error,
    final StackTrace? stackTrace,
  }) => EcsActionStatus(
    phase: phase ?? this.phase,
    runId: runId ?? this.runId,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    progress: progress ?? this.progress,
    result: result ?? this.result,
    error: error ?? this.error,
    stackTrace: stackTrace ?? this.stackTrace,
  );

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is EcsActionStatus &&
          phase == other.phase &&
          runId == other.runId &&
          startedAt == other.startedAt &&
          finishedAt == other.finishedAt &&
          progress == other.progress &&
          result == other.result &&
          error == other.error &&
          stackTrace == other.stackTrace;

  @override
  int get hashCode => Object.hash(
    phase,
    runId,
    startedAt,
    finishedAt,
    progress,
    result,
    error,
    stackTrace,
  );
}

/// Data-only resource containing action execution status by key.
///
/// This is intentionally an ECS resource instead of a Flutter notifier. Widgets
/// observe it through normal ecsly selectors.
class EcsActionStatusResource extends Resource {
  final Map<Object, EcsActionStatus> _statuses = <Object, EcsActionStatus>{};

  EcsActionStatus statusOf(final Object key) =>
      _statuses[key] ?? const EcsActionStatus.idle();

  bool isRunning(final Object key) => statusOf(key).isRunning;

  Map<Object, EcsActionStatus> get statuses => Map.unmodifiable(_statuses);

  @internal
  void setStatus(final Object key, final EcsActionStatus status) {
    _statuses[key] = status;
  }

  @internal
  void clearStatus(final Object key) {
    _statuses.remove(key);
  }
}

/// Minimal dependency registry for headless [EcsAction] tests and apps.
///
/// Apps may still use their own DI. This registry exists so actions can remain
/// Flutter-free without requiring a specific service locator package.
class EcsActionServices {
  EcsActionServices([final Map<Type, Object>? services])
    : _services = Map<Type, Object>.of(services ?? const <Type, Object>{});

  final Map<Type, Object> _services;

  bool has<T extends Object>() => _services.containsKey(T);

  T read<T extends Object>() {
    final service = _services[T];
    if (service is T) return service;
    throw StateError('No EcsAction service registered for $T.');
  }

  void upsert<T extends Object>(final T service) {
    _services[T] = service;
  }
}

/// Cooperative cancellation token passed to actions.
class EcsActionCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const EcsActionCancelledException();
    }
  }
}

/// Exception thrown when an action cooperatively observes cancellation.
class EcsActionCancelledException implements Exception {
  const EcsActionCancelledException();

  @override
  String toString() => 'EcsActionCancelledException';
}

/// Context passed to reusable app actions.
class EcsActionContext {
  EcsActionContext({
    required this.world,
    required this.services,
    required this.statusKey,
    required this.runId,
    required this.cancellationToken,
    required this.setProgress,
    required this.runAction,
  });

  final World world;
  final EcsActionServices services;
  final Object statusKey;
  final int runId;
  final EcsActionCancellationToken cancellationToken;
  final void Function(double? progress) setProgress;
  final Future<T> Function<T>(EcsAction<T> action) runAction;
  EcsInvalidationBatch _invalidation = const EcsInvalidationBatch.empty();
  bool _hasExplicitInvalidation = false;

  T readResource<T extends Resource>() => world.getResource<T>();

  T getResource<T extends Resource>() => readResource<T>();

  T? maybeReadResource<T extends Resource>() => world.maybeGetResource<T>();

  T? maybeGetResource<T extends Resource>() => maybeReadResource<T>();

  Entity findEntityWithComponent<T extends Component>({
    required final EcsComponentWhere<T> where,
  }) => world.findEcsEntityWithComponent<T>(where: where);

  Entity? maybeFindEntityWithComponent<T extends Component>({
    required final EcsComponentWhere<T> where,
  }) => world.maybeFindEcsEntityWithComponent<T>(where: where);

  T getComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) => world.getEcsComponent<T>(entity: entity, where: where);

  T? maybeGetComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) => world.maybeGetEcsComponent<T>(entity: entity, where: where);

  T readComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) => getComponent<T>(entity: entity, where: where);

  T? maybeReadComponent<T extends Component>({
    required final Entity entity,
    final EcsComponentWhere<T>? where,
  }) => maybeGetComponent<T>(entity: entity, where: where);

  T readService<T extends Object>() => services.read<T>();

  bool hasService<T extends Object>() => services.has<T>();

  Future<T> run<T>(final EcsAction<T> action) => runAction(action);

  void mutateResource<T extends Resource>(final void Function(T resource) run) {
    run(getResource<T>());
    invalidateResource<T>();
  }

  void upsertResource<T extends Resource>(final T resource) {
    world.upsertResource(resource);
    invalidateResource<T>();
  }

  EntityCommands upsertComponent<T extends Component>(
    final Entity entity,
    final T component, {
    final bool structural = false,
  }) {
    final commands = world.upsertComponent<T>(entity, component);
    invalidateComponent<T>(entity: entity, structural: structural);
    return commands;
  }

  Entity spawnComponentBundle(final ComponentBundle bundle) {
    invalidateStructural();
    return world.spawnComponentBundle(bundle);
  }

  Entity spawnComponents(
    final List<Component> components, [
    final List<(Type, Type)> extensionComponents = const [],
  ]) {
    invalidateStructural();
    return world.spawnComponents(components, extensionComponents);
  }

  void invalidate(final EcsInvalidationBatch batch) {
    _hasExplicitInvalidation = true;
    _invalidation = _invalidation.merge(batch);
  }

  void invalidateBroad() => invalidate(const EcsInvalidationBatch.broad());

  void invalidateStructural() =>
      invalidate(EcsInvalidationBatch.structuralChange());

  void invalidateResource<T extends Resource>() =>
      invalidate(EcsInvalidationBatch.resource<T>());

  void invalidateComponent<T extends Component>({
    final Entity? entity,
    final bool structural = false,
  }) => invalidate(
    EcsInvalidationBatch.component<T>(entity: entity, structural: structural),
  );

  @internal
  EcsInvalidationBatch invalidationOrBroad() => _hasExplicitInvalidation
      ? _invalidation
      : const EcsInvalidationBatch.broad();

  void cancelIfRequested() => cancellationToken.throwIfCancelled();
}

/// Reusable app-level workflow over an ecsly [World].
///
/// Keep [EcsCommand] for structural ECS operations. [EcsAction] is for app
/// use-cases such as submit form, sign in, save draft, optimistic publish, or
/// hydrate local state.
abstract class EcsAction<TResult> {
  const EcsAction();

  /// Key used to expose status in [EcsActionStatusResource].
  ///
  /// Override this for independent instances of the same action type.
  Object get statusKey => runtimeType;

  FutureOr<TResult> run(final EcsActionContext context);
}
