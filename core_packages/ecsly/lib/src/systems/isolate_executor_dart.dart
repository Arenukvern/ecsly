import 'dart:async';
import 'dart:isolate';

import 'isolate_executor.dart';

/// Default isolate executor for framework-agnostic ECS core
/// Uses Dart isolates as the default implementation
const IsolateExecutor defaultIsolateExecutor = IsolateExecutorDart();

/// {@template isolate_executor_dart}
/// Default isolate executor using Dart's built-in Isolate.run.
/// Provides fallback isolate execution for non-Flutter environments.
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
