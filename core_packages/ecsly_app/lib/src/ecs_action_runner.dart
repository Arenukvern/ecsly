import 'dart:async';

import 'package:ecsly/ecsly.dart';

import 'ecs_action.dart';
import 'ecs_invalidation_batch.dart';

typedef EcsActionChanged =
    void Function({bool flush, EcsInvalidationBatch? invalidation});
typedef EcsActionAfterRun =
    FutureOr<EcsInvalidationBatch?> Function(
      EcsInvalidationBatch actionInvalidation,
    );

/// Pure Dart runner for reusable app-level [EcsAction] workflows.
///
/// Hosts can pass [onChanged] to bridge status/resource changes into their own
/// notification system. Flutter uses this to notify widgets; headless tests or
/// CLI tools may omit it and inspect [EcsActionStatusResource] directly.
class EcsActionRunner {
  EcsActionRunner({required this.world, final EcsActionServices? services})
    : services = services ?? EcsActionServices();

  final World world;
  final EcsActionServices services;

  int _nextActionRunId = 0;

  Future<T> run<T>(
    final EcsAction<T> action, {
    final bool flush = true,
    final EcsActionChanged? onChanged,
    final EcsActionAfterRun? afterRun,
  }) async {
    final key = action.statusKey;
    final runId = ++_nextActionRunId;
    final startedAt = DateTime.now();
    final token = EcsActionCancellationToken();

    _setActionStatus(
      key,
      EcsActionStatus(
        phase: EcsActionPhase.running,
        runId: runId,
        startedAt: startedAt,
      ),
      flush: flush,
      onChanged: onChanged,
    );

    final context = EcsActionContext(
      world: world,
      services: services,
      statusKey: key,
      runId: runId,
      cancellationToken: token,
      setProgress: (final progress) {
        final current = actionStatusOf(key);
        if (current.runId != runId || !current.isRunning) return;
        _setActionStatus(
          key,
          current.copyWith(progress: progress),
          onChanged: onChanged,
        );
      },
      runAction: <TNested>(final nestedAction) =>
          run<TNested>(nestedAction, flush: flush, onChanged: onChanged),
    );

    try {
      final result = await action.run(context);
      if (!_isCurrentActionRun(key, runId)) {
        return result;
      }
      if (afterRun != null && flush) {
        world.flush();
      }
      var worldInvalidation = context.invalidationOrBroad();
      final afterRunInvalidation = await afterRun?.call(worldInvalidation);
      if (afterRunInvalidation != null) {
        worldInvalidation = worldInvalidation.merge(afterRunInvalidation);
      }
      if (token.isCancelled) {
        _setActionStatus(
          key,
          EcsActionStatus(
            phase: EcsActionPhase.cancelled,
            runId: runId,
            startedAt: startedAt,
            finishedAt: DateTime.now(),
          ),
          flush: flush,
          onChanged: onChanged,
          invalidation: worldInvalidation,
        );
        throw const EcsActionCancelledException();
      }
      _setActionStatus(
        key,
        EcsActionStatus(
          phase: EcsActionPhase.succeeded,
          runId: runId,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          result: result,
        ),
        flush: flush,
        onChanged: onChanged,
        invalidation: worldInvalidation,
      );
      return result;
    } on EcsActionCancelledException catch (error, stackTrace) {
      if (!_isCurrentActionRun(key, runId)) rethrow;
      _setActionStatus(
        key,
        EcsActionStatus(
          phase: EcsActionPhase.cancelled,
          runId: runId,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          error: error,
          stackTrace: stackTrace,
        ),
        flush: flush,
        onChanged: onChanged,
        invalidation: context.invalidationOrBroad(),
      );
      rethrow;
    } on Object catch (error, stackTrace) {
      if (!_isCurrentActionRun(key, runId)) rethrow;
      _setActionStatus(
        key,
        EcsActionStatus(
          phase: EcsActionPhase.failed,
          runId: runId,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          error: error,
          stackTrace: stackTrace,
        ),
        flush: flush,
        onChanged: onChanged,
        invalidation: context.invalidationOrBroad(),
      );
      rethrow;
    }
  }

  /// Returns the latest status for [key].
  EcsActionStatus actionStatusOf(final Object key) {
    final statusResource = _ensureActionStatusResource();
    return statusResource.statusOf(key);
  }

  EcsActionStatusResource _ensureActionStatusResource() {
    if (!world.resources.has<EcsActionStatusResource>()) {
      world.upsertResource(EcsActionStatusResource());
      world.flushResourcesOnly();
    }
    return world.getResource<EcsActionStatusResource>();
  }

  void _setActionStatus(
    final Object key,
    final EcsActionStatus status, {
    final bool flush = true,
    final EcsActionChanged? onChanged,
    final EcsInvalidationBatch invalidation =
        const EcsInvalidationBatch.empty(),
  }) {
    _ensureActionStatusResource().setStatus(key, status);
    final statusInvalidation =
        EcsInvalidationBatch.resource<EcsActionStatusResource>();
    onChanged?.call(
      flush: flush,
      invalidation: statusInvalidation.merge(invalidation),
    );
  }

  bool _isCurrentActionRun(final Object key, final int runId) =>
      actionStatusOf(key).runId == runId;
}
