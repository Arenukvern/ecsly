import 'dart:async';
import 'dart:isolate';

import 'package:async_parallel/async_parallel.dart';

/// {@template isolate_executor_pool_dart}
/// Pooled isolate executor that amortizes isolate startup cost.
///
/// [IsolateExecutorDart] spawns a fresh isolate per call (~ms startup).
/// [IsolateExecutorPoolDart] keeps worker isolates alive and dispatches work
/// to idle workers, reusing them across calls.
///
/// ## Constraint
///
/// The worker entry point must be a **top-level or static function**. A
/// long-lived isolate cannot receive new closures per message — the work logic
/// is fixed at pool construction.
///
/// ## Wire protocol
///
/// Each [compute] call sends `[SendPort replyTo, Object? payload]` to a worker
/// and awaits exactly one reply on `replyTo`. The reply must be a two-element
/// list `[bool ok, Object? value]` — `ok: true` completes the future with
/// `value`, `ok: false` completes it with an error.
///
/// ## Use with BufferedScheduleJobSystem
///
/// When paired with [BufferedScheduleJobSystem], the worker entry point
/// receives `[SendPort replyTo, TransferableTypedData chunk]` and replies with
/// `[true, TransferableTypedData result]`. The chunk input is zero-copy
/// transferred; only the result buffer is copied back (typically small).
/// {@endtemplate}
class IsolateExecutorPoolDart extends IsolateExecutor {
  /// {@macro isolate_executor_pool_dart}
  IsolateExecutorPoolDart({
    required final void Function(SendPort ownerSendPort) workerEntry,
    final int size = 4,
    final Duration? idleTimeout,
  }) : _pool = IsolateExecutorPool(
         workerEntry,
         size: size,
         idleTimeout: idleTimeout,
       );

  final IsolateExecutorPool _pool;

  /// Number of worker isolates kept alive.
  int get size => _pool.size;

  @override
  Future<R> compute<Q, R>(
    final FutureOr<R> Function(Q message) function,
    final Q message,
  ) => IsolateExecutorPoolAdapter(_pool).compute<Q, R>(function, message);

  /// Shuts down all worker isolates and rejects pending work.
  Future<void> shutdown() => _pool.shutdown();
}
