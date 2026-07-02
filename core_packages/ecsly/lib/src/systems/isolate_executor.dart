// ignore_for_file: one_member_abstracts

import 'dart:async';

/// {@template isolate_executor}
/// Abstract interface for executing functions in isolates.
/// Provides framework-agnostic isolate execution with fallback to Dart isolates.
/// {@endtemplate}
abstract class IsolateExecutor {
  /// {@macro isolate_executor}
  const IsolateExecutor();

  /// Execute a function in an isolate and return the result.
  ///
  /// [function] - The function to execute (must be a top-level or static function)
  /// [message] - The message to pass to the isolate function
  /// Returns a Future that completes with the result of the function execution
  Future<R> compute<Q, R>(
    final FutureOr<R> Function(Q message) function,
    final Q message,
  );
}
