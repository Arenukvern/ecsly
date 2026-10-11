import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'isolate_executor.dart';

/// {@template isolate_executor_pool}
/// A pool of reusable isolates that amortizes isolate-startup cost.
///
/// [IsolateExecutorDart] spawns a fresh isolate per call. Isolate startup is
/// expensive (roughly milliseconds), so for many small, frequent tasks it
/// dominates wall-clock time. [IsolateExecutorPool] keeps [size] worker
/// isolates alive and dispatches messages to idle workers, reusing them across
/// calls.
///
/// ## Constraint
///
/// The worker entry point must be a **top-level or static function**. A
/// long-lived isolate cannot receive new closures per message — the work
/// logic is fixed at pool construction.
///
/// ## Wire protocol
///
/// Each [execute] sends `[SendPort replyTo, Object? payload]` to a worker and
/// awaits exactly one reply on `replyTo`. The reply must be a two-element list
/// `[bool ok, Object? value]` — `ok: true` completes the future with `value`,
/// `ok: false` completes it with an error. A worker that dies mid-task (or a
/// spawn that fails) completes its callers with a [StateError] instead of
/// hanging.
///
/// ## Use as an [IsolateExecutor]
///
/// [IsolateExecutorPool] is intentionally **not** an [IsolateExecutor]: that
/// interface passes a per-call closure, which a long-lived pool worker cannot
/// run. Wrap the pool with [IsolateExecutorPoolAdapter] to plug it into layers
/// that expect [IsolateExecutor] (for example a job system's `isolateExecutor`).
/// {@endtemplate}
class IsolateExecutorPool {
  /// {@macro isolate_executor_pool}
  IsolateExecutorPool(
    this._workerEntry, {
    this.size = 2,
    this.idleTimeout,
    this.spawnTimeout = const Duration(seconds: 10),
  }) : assert(size > 0, 'pool size must be positive');

  /// Top-level worker entry point.
  ///
  /// Announces a port to [ownerSendPort], then processes work items sent to
  /// that port. Each item must be a two-element list
  /// `[SendPort replyTo, Object? payload]`; the worker sends exactly one reply
  /// on `replyTo` per item, as a `[bool ok, Object? value]` envelope.
  final void Function(SendPort ownerSendPort) _workerEntry;

  /// Number of worker isolates kept alive.
  final int size;

  /// How long to retain an idle worker before shutting it down.
  ///
  /// `null` keeps workers alive indefinitely. A timed-out worker RETIRES:
  /// it leaves the pool, and capacity is re-spawned on the next [execute]
  /// that needs it (the old behavior left the dead worker in the list and
  /// permanently shrank the pool).
  final Duration? idleTimeout;

  /// How long to wait for a spawned worker's announce (its first message —
  /// the reply [SendPort]). A worker entry that never announces must not
  /// hang the pool forever: on timeout the spawn fails and the queue's
  /// callers get a [StateError].
  final Duration spawnTimeout;

  final List<_PoolWorker> _workers = <_PoolWorker>[];
  final Queue<_PendingWork> _queue = Queue<_PendingWork>();

  /// Workers whose [Isolate.spawn] is still in flight — they count toward
  /// [size] so a burst of enqueues cannot over-spawn (the old code counted
  /// only completed spawns and launched one worker per racing enqueue).
  int _spawning = 0;

  bool _shutdown = false;

  /// Submits [payload] to an idle worker and completes with the reply value.
  ///
  /// Completes with a [StateError] if the pool was shut down, a worker died
  /// mid-task, or no worker could be spawned.
  Future<R> execute<R>(final Object? payload) {
    if (_shutdown) {
      throw StateError('IsolateExecutorPool has been shut down');
    }
    final completer = Completer<R>();
    _enqueue(_PendingWork(payload, completer));
    return completer.future;
  }

  /// Shuts down all worker isolates. Queued AND in-flight work completes
  /// with a [StateError] instead of hanging; isolates still spawning when
  /// [shutdown] lands are killed once they come up (no leak).
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    while (_queue.isNotEmpty) {
      final work = _queue.removeFirst();
      work.completer.completeError(StateError('IsolateExecutorPool shut down'));
    }
    for (final worker in List<_PoolWorker>.of(_workers)) {
      await worker.shutdown();
    }
    _workers.clear();
  }

  void _enqueue(final _PendingWork work) {
    _maybeSpawn();
    _queue.add(work);
    _pump();
  }

  void _maybeSpawn() {
    if (_shutdown) return;
    if (_workers.length + _spawning >= size) return;
    _spawning += 1;
    final worker = _PoolWorker(
      _workerEntry,
      idleTimeout: idleTimeout,
      spawnTimeout: spawnTimeout,
      onRetired: _onWorkerRetired,
      onIdle: _onWorkerIdle,
    );
    unawaited(
      worker.spawn().then((final _) {
        _spawning -= 1;
        if (_shutdown) {
          // The pool closed while this spawn was in flight.
          unawaited(worker.shutdown());
          return;
        }
        _workers.add(worker);
        _pump();
      }, onError: (final Object _) {
        _spawning -= 1;
        // Nothing can serve the queue if no worker ever came up.
        _failQueueIfNoCapacity();
      }),
    );
  }

  void _onWorkerRetired(final _PoolWorker worker) {
    _workers.remove(worker);
    // Retire/failure frees a capacity slot; keep the queue served.
    _maybeSpawn();
    _pump();
  }

  /// A worker finished its task and is idle again — the queue may be
  /// waiting on exactly this worker.
  void _onWorkerIdle(final _PoolWorker worker) {
    _pump();
  }

  void _failQueueIfNoCapacity() {
    if (_shutdown || _workers.isNotEmpty || _spawning > 0) return;
    while (_queue.isNotEmpty) {
      final work = _queue.removeFirst();
      work.completer.completeError(
        StateError('IsolateExecutorPool worker failed to spawn'),
      );
    }
  }

  void _pump() {
    if (_shutdown) return;
    while (_queue.isNotEmpty) {
      final worker = _idleWorker();
      if (worker == null) break;
      final work = _queue.removeFirst();
      worker.dispatch(work.payload, work.completer);
    }
  }

  _PoolWorker? _idleWorker() {
    for (final worker in _workers) {
      if (worker.isIdle) return worker;
    }
    return null;
  }
}

/// Adapts an [IsolateExecutorPool] to the [IsolateExecutor] interface.
///
/// [IsolateExecutor.compute] takes a per-call closure, which a long-lived
/// pool worker cannot run. This adapter accepts the closure for interface
/// compatibility but dispatches [payload] through the pool's fixed worker
/// entry — the entry point must implement the work the closure would have.
class IsolateExecutorPoolAdapter extends IsolateExecutor {
  /// {@template isolate_executor_pool_adapter}
  /// Wraps [pool] so it can be used wherever an [IsolateExecutor] is expected.
  /// {@endtemplate}
  IsolateExecutorPoolAdapter(this.pool);

  /// The underlying pool being adapted.
  final IsolateExecutorPool pool;

  @override
  Future<R> compute<Q, R>(
    final FutureOr<R> Function(Q message) function,
    final Q message,
  ) => pool.execute<R>(message as Object?);
}

/// A single worker isolate in an [IsolateExecutorPool].
class _PoolWorker {
  _PoolWorker(
    this._entryPoint, {
    this.idleTimeout,
    this.spawnTimeout = const Duration(seconds: 10),
    this.onRetired,
    this.onIdle,
  });

  final void Function(SendPort ownerSendPort) _entryPoint;
  final Duration? idleTimeout;
  final Duration spawnTimeout;

  /// Called when this worker leaves the pool for good: idle timeout, death
  /// mid-task, or a failed spawn. The pool refills the slot.
  final void Function(_PoolWorker worker)? onRetired;

  /// Called after each task completes (worker idle again) so the pool can
  /// serve queued work that was waiting for this worker.
  final void Function(_PoolWorker worker)? onIdle;

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _busy = false;
  bool _retired = false;

  /// The task currently dispatched to this worker, if any — shutdown and
  /// worker death must fail it instead of leaving the caller hanging.
  Completer<dynamic>? _inFlight;
  Timer? _idleTimer;

  bool get isIdle => _sendPort != null && !_busy;

  Future<void> spawn() async {
    final receivePort = ReceivePort();
    final exitPort = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
        _entryPoint,
        receivePort.sendPort,
        onExit: exitPort.sendPort,
      );
      // The announce races the spawn timeout: a worker entry that never
      // announces must fail the spawn, not hang the pool forever.
      _sendPort = await receivePort.first
          .timeout(
            spawnTimeout,
            onTimeout: () => throw TimeoutException(
              'pool worker never announced its port',
            ),
          )
          as SendPort;
    } on Object {
      receivePort.close();
      exitPort.close();
      _retired = true;
      rethrow;
    } finally {
      receivePort.close();
    }
    // Death BETWEEN tasks has no reply port to fail — the exit port is the
    // liveness signal that keeps the pool from dispatching into a corpse.
    unawaited(
      exitPort.first.whenComplete(exitPort.close).then((final _) {
        if (_retired) return;
        _retired = true;
        _cancelIdleTimer();
        _kill();
        final inFlight = _inFlight;
        _inFlight = null;
        _busy = false;
        if (inFlight != null && !inFlight.isCompleted) {
          inFlight.completeError(StateError('worker isolate died mid-task'));
        }
        onRetired?.call(this);
      }),
    );
  }

  void dispatch(final Object? payload, final Completer<dynamic> completer) {
    final sendPort = _sendPort;
    if (sendPort == null || _busy || _retired) {
      completer.completeError(StateError('pool worker is not available'));
      return;
    }
    _busy = true;
    _inFlight = completer;
    _cancelIdleTimer();
    final replyPort = ReceivePort();
    sendPort.send([replyPort.sendPort, payload]);
    late final StreamSubscription<dynamic> subscription;
    subscription = replyPort.listen(
      (final message) {
        if (message is List<Object?>) {
          final envelope = message;
          final ok = envelope[0]! as bool;
          final value = envelope[1];
          _finishTask();
          unawaited(subscription.cancel());
          replyPort.close();
          if (ok) {
            completer.complete(value);
          } else {
            completer.completeError(value ?? StateError('worker failed'));
          }
          // Queued work may be waiting on exactly this worker.
          onIdle?.call(this);
          _scheduleIdleShutdown();
        }
      },
      // The reply port closes without a message when the worker isolate
      // dies mid-task — fail the caller and leave the pool instead of
      // hanging forever.
      onDone: () {
        if (!_busy) return;
        _finishTask();
        _retire();
        completer.completeError(StateError('worker isolate died mid-task'));
      },
      onError: (final Object error) {
        _finishTask();
        unawaited(subscription.cancel());
        replyPort.close();
        completer.completeError(error);
        onIdle?.call(this);
        _scheduleIdleShutdown();
      },
    );
  }

  /// Clears the in-flight marker (completion itself is the caller's job).
  void _finishTask() {
    _busy = false;
    _inFlight = null;
  }

  void _scheduleIdleShutdown() {
    _cancelIdleTimer();
    final timeout = idleTimeout;
    if (timeout == null) return;
    _idleTimer = Timer(timeout, _retire);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Leaves the pool for good (idle timeout or death) and notifies the pool
  /// so it can refill the slot.
  void _retire() {
    if (_retired) return;
    _retired = true;
    _cancelIdleTimer();
    _kill();
    onRetired?.call(this);
  }

  Future<void> shutdown() async {
    _cancelIdleTimer();
    final inFlight = _inFlight;
    _inFlight = null;
    _retired = true;
    _kill();
    // A task dispatched at shutdown must not hang its caller.
    if (inFlight != null && !inFlight.isCompleted) {
      inFlight.completeError(StateError('IsolateExecutorPool shut down'));
    }
  }

  void _kill() {
    final isolate = _isolate;
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    _sendPort = null;
  }
}

/// Work submitted to an [IsolateExecutorPool] awaiting an idle worker.
class _PendingWork {
  _PendingWork(this.payload, this.completer);

  final Object? payload;
  final Completer<dynamic> completer;
}

/// {@template pool_worker_entry}
/// Example top-level worker entry for [IsolateExecutorPool].
///
/// Receives the owner's send port, announces its own port, then processes
/// `[SendPort replyTo, int payload]` items by sending `[true, doubled]` back.
/// {@endtemplate}
void examplePoolWorkerEntry(final SendPort ownerSendPort) {
  final port = ReceivePort();
  ownerSendPort.send(port.sendPort);
  port.listen((final message) {
    if (message is List<Object?>) {
      final pair = message;
      final replyTo = pair[0]! as SendPort;
      final value = pair[1]! as int;
      replyTo.send([true, value * 2]);
    }
  });
}
