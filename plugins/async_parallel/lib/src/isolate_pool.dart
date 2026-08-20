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
/// `ok: false` completes it with an error.
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
  IsolateExecutorPool(this._workerEntry, {this.size = 2, this.idleTimeout})
    : assert(size > 0, 'pool size must be positive');

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
  /// `null` keeps workers alive indefinitely.
  final Duration? idleTimeout;

  final List<_PoolWorker> _workers = <_PoolWorker>[];
  final Queue<_PendingWork> _queue = Queue<_PendingWork>();
  bool _shutdown = false;

  /// Submits [payload] to an idle worker and completes with the reply value.
  Future<R> execute<R>(final Object? payload) {
    if (_shutdown) {
      throw StateError('IsolateExecutorPool has been shut down');
    }
    final completer = Completer<R>();
    _enqueue(_PendingWork(payload, completer));
    return completer.future;
  }

  /// Shuts down all worker isolates and rejects pending work.
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    while (_queue.isNotEmpty) {
      final work = _queue.removeFirst();
      work.completer.completeError(StateError('IsolateExecutorPool shut down'));
    }
    for (final worker in _workers) {
      await worker.shutdown();
    }
    _workers.clear();
  }

  void _enqueue(final _PendingWork work) {
    if (_workers.length < size) {
      _spawnWorker();
    }
    _queue.add(work);
    _pump();
  }

  void _spawnWorker() {
    final worker = _PoolWorker(_workerEntry, idleTimeout: idleTimeout);
    unawaited(
      worker.spawn().then((final _) {
        _workers.add(worker);
        _pump();
      }),
    );
  }

  void _pump() {
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
  _PoolWorker(this._entryPoint, {this.idleTimeout});

  final void Function(SendPort ownerSendPort) _entryPoint;
  final Duration? idleTimeout;

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _busy = false;
  Timer? _idleTimer;

  bool get isIdle => _sendPort != null && !_busy;

  Future<void> spawn() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_entryPoint, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;
    receivePort.close();
  }

  void dispatch(final Object? payload, final Completer<dynamic> completer) {
    _busy = true;
    _cancelIdleTimer();
    final replyPort = ReceivePort();
    _sendPort!.send([replyPort.sendPort, payload]);
    replyPort.listen(
      (final message) {
        if (message is List<Object?>) {
          final envelope = message;
          final ok = envelope[0]! as bool;
          final value = envelope[1];
          replyPort.close();
          _busy = false;
          if (ok) {
            completer.complete(value);
          } else {
            completer.completeError(value ?? StateError('worker failed'));
          }
          _scheduleIdleShutdown();
        }
      },
      onError: (final error) {
        replyPort.close();
        _busy = false;
        completer.completeError(error);
        _scheduleIdleShutdown();
      },
    );
  }

  void _scheduleIdleShutdown() {
    _cancelIdleTimer();
    final timeout = idleTimeout;
    if (timeout == null) return;
    _idleTimer = Timer(timeout, _kill);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> shutdown() async {
    _cancelIdleTimer();
    _kill();
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
