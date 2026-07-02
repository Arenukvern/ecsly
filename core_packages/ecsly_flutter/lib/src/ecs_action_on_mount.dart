import 'dart:async';

import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';
import 'ecs_controller.dart';
import 'ecs_scope.dart';

typedef EcsActionErrorCallback = void Function(Object error, StackTrace stack);

/// Runs an [EcsAction] once after this widget is mounted.
///
/// This is useful for app hydration, route loading, and other startup work that
/// should be expressed as normal ECS app logic instead of running before
/// `runApp`.
class EcsActionOnMount<T> extends StatefulWidget {
  const EcsActionOnMount({
    required this.action,
    required this.child,
    super.key,
    this.controller,
    this.enabled = true,
    this.runKey,
    this.onComplete,
    this.onError,
  });

  final EcsAction<T> action;
  final Widget child;
  final EcsController? controller;
  final bool enabled;
  final Object? runKey;
  // ignore: unsafe_variance, callback consumes T only after this action resolves.
  final ValueChanged<T>? onComplete;
  final EcsActionErrorCallback? onError;

  @override
  State<EcsActionOnMount<T>> createState() => _EcsActionOnMountState<T>();
}

class _EcsActionOnMountState<T> extends State<EcsActionOnMount<T>> {
  Object? _lastRunKey;
  Future<T>? _running;

  Object get _effectiveRunKey => widget.runKey ?? widget.action.statusKey;

  @override
  Widget build(final BuildContext context) => widget.child;

  @override
  void initState() {
    super.initState();
    _scheduleRun();
  }

  @override
  void didUpdateWidget(covariant final EcsActionOnMount<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) return;
    if (!oldWidget.enabled ||
        oldWidget.controller != widget.controller ||
        oldWidget.runKey != widget.runKey ||
        oldWidget.action.statusKey != widget.action.statusKey) {
      _scheduleRun();
    }
  }

  void _scheduleRun() {
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      if (!mounted || !widget.enabled) return;
      final runKey = _effectiveRunKey;
      if (_lastRunKey == runKey) return;
      _lastRunKey = runKey;

      final controller =
          widget.controller ?? EcsScope.requireControllerOf(context);
      final future = controller.runAction(widget.action);
      _running = future;
      unawaited(
        future.then<void>(
          (final result) {
            if (!mounted || !identical(_running, future)) return;
            widget.onComplete?.call(result);
          },
          onError: (final Object error, final StackTrace stackTrace) {
            if (!mounted || !identical(_running, future)) return;
            widget.onError?.call(error, stackTrace);
          },
        ),
      );
    });
  }
}
