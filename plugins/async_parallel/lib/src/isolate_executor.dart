import 'dart:async';
import 'dart:isolate';

// ignore_for_file: one_member_abstracts — pluggable backend seam, intentionally subclassed.
/// {@template isolate_executor}
/// Abstract interface for executing functions in isolates.
///
/// Provides a framework-agnostic, pluggable backend for offloading work to
/// background isolates. Concrete implementations may use Dart's built-in
/// [Isolate.run], a reusable isolate pool, or a native backend.
///
/// This abstraction exists so that higher layers (ECS job systems, game
/// pipelines) can request isolate execution without depending on a specific
/// isolate strategy. Swap the implementation to change the execution model
/// without touching the callers.
/// {@endtemplate}
abstract class IsolateExecutor {
  /// {@macro isolate_executor}
  const IsolateExecutor();

  /// Execute a function in an isolate and return its result.
  ///
  /// [function] must be a top-level or static function, or a closure that
  /// captures only sendable values. [message] is passed as the single
  /// argument to [function].
  ///
  /// Returns a Future that completes with the result of the function
  /// execution, or with an error if the isolate fails.
  Future<R> compute<Q, R>(
    final FutureOr<R> Function(Q message) function,
    final Q message,
  );
}

/// {@template isolate_executor_dart}
/// Default isolate executor using Dart's built-in [Isolate.run].
///
/// Spawns a fresh isolate per call. Simple and correct, but isolate startup is
/// expensive (roughly milliseconds), so this is a poor fit for many small,
/// frequent tasks. Prefer a pooled implementation for hot paths.
/// {@endtemplate}
class IsolateExecutorDart extends IsolateExecutor {
  /// {@macro isolate_executor_dart}
  const IsolateExecutorDart();

  @override
  Future<R> compute<Q, R>(
    final FutureOr<R> Function(Q message) function,
    final Q message,
  ) => Isolate.run(() => function(message));
}

/// The default isolate executor used when none is specified.
const IsolateExecutor defaultIsolateExecutor = IsolateExecutorDart();
