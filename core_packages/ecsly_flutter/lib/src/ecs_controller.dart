import 'dart:async';

import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/foundation.dart';

import 'ecs_schedule_observer.dart';
import 'ecs_selector_dependencies.dart';

/// Flutter-facing notifier for an ecsly [World].
///
/// Apps can mutate ECS state through transactions and notify widgets once.
/// Game/prototype loops can reuse the same controller as their frame signal.
class EcsController extends ChangeNotifier {
  EcsController({
    required this.world,
    EcsActionServices? services,
    this.afterActionSchedule,
    this.afterActionScheduleSpec,
    this.onScheduleRun,
  }) : services = services ?? EcsActionServices() {
    _actionRunner = EcsActionRunner(world: world, services: this.services);
  }

  final World world;
  final EcsActionServices services;
  String? afterActionSchedule;
  EcsHostSchedule? afterActionScheduleSpec;
  EcsScheduleRunObserver? onScheduleRun;

  bool _disposed = false;
  late final EcsActionRunner _actionRunner;
  EcsInvalidationBatch _lastInvalidation = const EcsInvalidationBatch.broad();
  int _notificationRevision = 0;

  /// App/host invalidation for the most recent notification.
  EcsInvalidationBatch get lastInvalidation => _lastInvalidation;

  /// Monotonic notification revision for Flutter inherited-model invalidation.
  int get notificationRevision => _notificationRevision;

  EcsControllerChangeView get changeView =>
      EcsControllerChangeView(world: world, invalidation: _lastInvalidation);

  /// Flushes pending ECS changes, then notifies Flutter listeners.
  void notifyWorldChanged({
    bool flush = true,
    EcsInvalidationBatch? invalidation,
  }) {
    _notifyWorldChanged(flush: flush, invalidation: invalidation);
  }

  void _notifyWorldChanged({
    required bool flush,
    EcsInvalidationBatch? invalidation,
  }) {
    if (_disposed) return;
    if (flush) {
      world.flush();
    }
    _lastInvalidation = invalidation ?? const EcsInvalidationBatch.broad();
    _notificationRevision += 1;
    notifyListeners();
  }

  /// Runs a synchronous ECS transaction and notifies listeners once.
  T runTransaction<T>(
    T Function(World world) transaction, {
    bool flush = true,
    EcsInvalidationBatch? invalidation,
  }) {
    final result = transaction(world);
    _notifyWorldChanged(flush: flush, invalidation: invalidation);
    return result;
  }

  /// Runs an asynchronous ECS transaction and notifies listeners once.
  Future<T> runAsyncTransaction<T>(
    FutureOr<T> Function(World world) transaction, {
    bool flush = true,
    EcsInvalidationBatch? invalidation,
  }) async {
    final result = await transaction(world);
    _notifyWorldChanged(flush: flush, invalidation: invalidation);
    return result;
  }

  /// Runs a reusable app action and exposes its status through ECS resources.
  Future<T> runAction<T>(
    EcsAction<T> action, {
    bool flush = true,
    String? afterActionSchedule,
    EcsHostSchedule? afterActionScheduleSpec,
  }) => _actionRunner.run<T>(
    action,
    flush: flush,
    afterRun: (actionInvalidation) {
      final schedule =
          afterActionScheduleSpec ??
          _hostScheduleFrom(afterActionSchedule) ??
          this.afterActionScheduleSpec ??
          _hostScheduleFrom(this.afterActionSchedule);
      if (schedule == null || !schedule.shouldRun(actionInvalidation)) {
        return const EcsInvalidationBatch.empty();
      }
      return runSchedule(
        schedule.name,
        flush: false,
        notify: false,
        invalidation: schedule.invalidation,
        reason: EcsFlutterScheduleReason.afterAction,
      );
    },
    onChanged: ({flush = true, invalidation}) =>
        _notifyWorldChanged(
          flush: flush,
          invalidation:
              invalidation ??
              EcsInvalidationBatch.resource<EcsActionStatusResource>(),
        ),
  );

  EcsInvalidationBatch runSchedule(
    String scheduleName, {
    bool flush = true,
    bool notify = true,
    EcsInvalidationBatch? invalidation,
    EcsFlutterScheduleReason reason = EcsFlutterScheduleReason.onMount,
  }) {
    final stopwatch = Stopwatch()..start();
    final effectiveInvalidation =
        invalidation ?? const EcsInvalidationBatch.broad();
    try {
      world.runSchedule(ScheduleId(scheduleName));
      stopwatch.stop();
      onScheduleRun?.call(
        EcsScheduleRunEvent(
          scheduleName: scheduleName,
          reason: reason,
          elapsed: stopwatch.elapsed,
        ),
      );
      if (notify) {
        _notifyWorldChanged(flush: flush, invalidation: effectiveInvalidation);
      } else if (flush) {
        world.flush();
      }
      return effectiveInvalidation;
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      onScheduleRun?.call(
        EcsScheduleRunEvent(
          scheduleName: scheduleName,
          reason: reason,
          elapsed: stopwatch.elapsed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  /// Returns the latest status for [key].
  EcsActionStatus actionStatusOf(Object key) =>
      _actionRunner.actionStatusOf(key);

  bool shouldRefreshResource<T extends Resource>() =>
      _lastInvalidation.matchesResourceType(T);

  bool shouldRefreshComponent<T extends Component>({Entity? entity}) =>
      _lastInvalidation.matchesComponentType(T, entity: entity);

  bool shouldRefreshWorld(EcsWorldSelectorDependencies? dependencies) {
    if (dependencies == null) return true;
    if (dependencies.structural && _lastInvalidation.matchesStructural()) {
      return true;
    }
    for (final type in dependencies.resourceTypes) {
      if (_lastInvalidation.matchesResourceType(type)) return true;
    }
    for (final type in dependencies.componentTypes) {
      if (_lastInvalidation.matchesComponentType(type)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

EcsHostSchedule? _hostScheduleFrom(String? name) =>
    name == null ? null : EcsHostSchedule(name);
